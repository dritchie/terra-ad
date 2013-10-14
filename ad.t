local templatize = terralib.require("templatize")
local Vector = terralib.require("vector")
local util = terralib.require("util")
local MemoryPool = terralib.require("memoryPool")


-- =============== GLOBALS ===============

-- TODO: Make this stuff thread-safe?

-- Global memory pool
local memPool = global(MemoryPool)

-- Global stack of variables active for the current computation
local VoidPtr = &opaque
local AdjointFn = {VoidPtr} -> {}
local struct TapeEntry
{
	datum: VoidPtr,
	fn: AdjointFn
}
local tape = global(Vector(TapeEntry))

local terra initGlobals()
	memPool:__construct()
	tape:__construct()
end

initGlobals()

-- =============== DUAL NUMBER TYPE GENERATION ===============

-- Generate a list of expression that refer to sequential anonymous
-- fields in a struct instance
local function makeFieldExpList(obj, numFields)
	local fields = {}
	for i=1,numFields do
		table.insert(fields, `obj.[string.format("_%d", i-1)])
	end
	return fields
end

-- The inner dual number type
local DualNum = templatize(function (...)

	local struct DualNumT
	{
		val: double,	-- Value
		adj: double,	-- Adjoint
	}

	-- Add extra entries from the argument type list
	-- These 'anonymous' fields will be named _0, _1, etc.
	local numExtraFields = select("#",...)
	for i=1,numExtraFields do
		table.insert(DualNumT.entries, (select(i,...)))
	end

	-- All dual nums are allocated from the memory pool
	DualNumT.methods.new = macro(function(val, adjFn, ...)
		local args = {}
		for i=1,numExtraFields do
			table.insert(args, (select(i, ...)))
		end
		return quote
			var dnptr = [&DualNumT](memPool:alloc(sizeof(DualNumT)))
			dnptr.val = val
			dnptr.adj = 0.0
			[makeFieldExpList(dnptr, numExtraFields)] = [args]
			var tapeEntry : TapeEntry
			tapeEntry.datum = dnptr
			tapeEntry.fn = adjFn
			tape:push(tapeEntry)
		in
			dnptr
		end
	end)

	return DualNumT
end)
local DualNumBase = DualNum()

-- The externally-visible dual number type
local struct num
{
	impl: &DualNumBase
}

terra num:val()
	return self.impl.val
end

terra num:adj()
	return self.impl.adj
end

local terra nullAdjointFn(impl: VoidPtr)
end

num.metamethods.__cast = function(from, to, exp)
	if from == double and to == num then
		return `num { DualNumBase.new(exp, nullAdjointFn) }
	else
		error(string.format("ad.t: Cannot cast '%s' to 'num'", tostring(from)))
	end
end


-- =============== FUNCTION GENERATION ===============

local cmath = terralib.includec("math.h")

local function makeADFunction(argTypes, fwdFn, adjFn, usedArgIndices)

	local params = {}
	local paramsimpl = {}
	local paramvals = {}
	for i,t in ipairs(argTypes) do
		if t == &DualNumBase then
			t = num
		end
		local sym = symbol(t)
		table.insert(params, sym)
		if t == num then
			table.insert(paramsimpl, `sym.impl)
			table.insert(paramvals, `sym.impl.val)
		else
			table.insert(paramsimpl, sym)
			table.insert(paramvals, sym)
		end
	end

	local retfn = nil
	if adjFn then
		local templateTypes = util.index(argTypes, usedArgIndices)
		local adjUsedParams = util.index(paramsimpl, usedArgIndices)
		local DN = DualNum(unpack(templateTypes))
		retfn = terra([params]) : num
			return num { [&DualNumBase](DN.new(fwdFn([paramvals]), adjFn, [adjUsedParams])) }
		end
	else
		retfn = terra([params])
			return fwdFn([paramvals])
		end
	end
	-- These functions are supposed to be (ideally) no slower than their cmath
	-- equivalents, so we always inline them.
	retfn:getdefinitions()[1]:setinlined(true)
	return retfn
end

local function makeOverloadedADFunction(numArgs, fwdFn, adjFnTemplate)
	local overallfn = nil
	local numVariants = 2 ^ numArgs
	local bitstring = 1
	for i=1,numVariants-1 do
		local types = {}
		for j=0,numArgs-1 do
			if bit.band(bit.tobit(2^j), bit.tobit(bitstring)) == 0 then
				table.insert(types, double)
			else
				table.insert(types, &DualNumBase)
			end
		end
		local adjFn, usedargindices = nil, nil
		if adjFnTemplate then 
			adjFn, usedargindices = adjFnTemplate(unpack(types))
		end
		local fn = makeADFunction(types, fwdFn, adjFn, usedargindices)
		if not overallfn then
			overallfn = fn
		else
			overallfn:adddefinition(fn:getdefinitions()[1])
		end
		bitstring = bitstring + 1
	end
	return overallfn
end

local function getvalue(terraquote)
	assert(terraquote.tree.expression.value)
	return terraquote.tree.expression.value
end

-- Extract the numeric value from a number regardless of whether
--    it is a double or a dual number.
-- Record which values have been extracted during adjoint function
--    construction.
local usedargtable = nil
local val = macro(function(v)
	usedargtable[getvalue(v)] = true
	if v:gettype() == double then
		return v
	else
		return `v.val
	end
end)

-- Extract the adjoint from a variable
-- (A no-op if the variable is actually a constant)
-- Record which adjoints have been extracted during adjoint function
--    construction.
local adj = macro(function(v)
	if v:gettype() ~= double then
		usedargtable[getvalue(v)] = true
		return `v.adj
	else
		return 0.0
	end
end)

-- Set the adjoint of a particular variable
-- (Performs a no-op if the variable is actually a constant)
-- Record which adjoints have been set during adjoint function
--   construction.
local setadj = macro(function(v, adjval)
	if v:gettype() ~= double then
		usedargtable[getvalue(v)] = true
		return quote
			v.adj = adjval
		end
	else
		return quote end
	end
end)

-- Make an adjoint function template
-- When choosing the DualNum type, only templatize on the arguments
--   the are actually used (values or adjoints) in the adjoint function.
--   The indices of these arguments are in the second return value.
local function adjoint(fntemp)
	return function(...)
		local specializedfn = fntemp(...)
		util.inline(specializedfn)
		usedargtable = {}
		specializedfn:compile()

		-- Match up used arguments with their types
		local usedtypeindices = {}
		local usedtypes = {}
		local adjfnparams = specializedfn:getdefinitions()[1].typedtree.parameters
		for i,arg in ipairs(adjfnparams) do
			-- Skip arg 1, b/c that's the var itself
			if i ~= 1 then
				if usedargtable[arg.symbol] then
					table.insert(usedtypeindices, i-1)
					table.insert(usedtypes, arg.type)
				end
			end
		end	
		local DN = DualNum(unpack(usedtypes))

		-- Construct the list of arguments that will be passed to the adjoint function
		-- These will be either fields on the dual num struct, or dummy values (for arguments
		--    that are unused for this particular specialization of the function). 
		local function makeArgsToAdjFn(dnum)
			local argstoadjfn = {}
			local currFieldIndex = 0
			for i,arg in ipairs(adjfnparams) do
				if i ~= 1 then
					if usedargtable[arg.symbol] then
						table.insert(argstoadjfn, `dnum.[string.format("_%d", currFieldIndex)])
						currFieldIndex = currFieldIndex + 1
					else
						table.insert(argstoadjfn, `[arg.type](0))
					end
				end
			end
			return argstoadjfn
		end

		-- Wrap the adjoint function (This is the version that will ultimately be called during
		--    gradient computation)
		local wrappedfn = terra(impl: VoidPtr)
			var dnum = [&DN](impl)
			specializedfn([&DualNumBase](dnum), [makeArgsToAdjFn(dnum)])
		end

		usedargtable = nil
		return wrappedfn, usedtypeindices
	end
end


-- =============== INSTANTIATE ALL THE FUNCTIONS! ===============

local admath = util.copytable(cmath)

local function addADFunction_simple(name, fn)
	local primalfn = admath[name]
	if not primalfn then
		error(string.format("ad.t: Cannot add overloaded dual function '%s' for which there is no primal function in cmath", name))
	end
	for i,def in ipairs(fn:getdefinitions()) do
		primalfn:adddefinition(def)
	end
end

local function addADFunction_overloaded(name, numArgs, fwdFn, adjFnTemplate)
	local dualfn = makeOverloadedADFunction(numArgs, fwdFn, adjFnTemplate)
	addADFunction_simple(name, dualfn)
end

local function addADFunction(...)
	if select("#",...) == 2 then
		addADFunction_simple(...)
	else
		addADFunction_overloaded(...)
	end
end

local function addADOperator(metamethodname, numArgs, fwdFn, adjFnTemplate)
	local fn = makeOverloadedADFunction(numArgs, fwdFn, adjFnTemplate)
	num.metamethods[metamethodname] = fn
end


---- Operators ----

-- ADD
addADOperator("__add", 2,
terra(a: double, b: double)
	return a + b
end,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, a: T1, b: T2)
		setadj(a, adj(a) + v.adj)
		setadj(b, adj(b) + v.adj)
	end
end))

-- SUB
addADOperator("__sub", 2,
terra(a: double, b: double)
	return a - b
end,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, a: T1, b: T2)
		setadj(a, adj(a) + v.adj)
		setadj(b, adj(b) - v.adj)
	end
end))

-- MUL
addADOperator("__mul", 2,
terra(a: double, b: double)
	return a * b
end,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, a: T1, b: T2)
		setadj(a, adj(a) + val(b)*v.adj)
		setadj(b, adj(b) + val(a)*v.adj)
	end
end))

-- DIV
addADOperator("__div", 2,
terra(a: double, b: double)
	return a / b
end,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, a: T1, b: T2)
		setadj(a, adj(a) + v.adj/val(b))
		setadj(b, adj(b) - v.adj*val(a)/(val(b)*val(b)))
	end
end))

-- UNM
addADOperator("__unm", 1,
terra(a: double)
	return -a
end,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) - v.adj)
	end
end))

-- EQ
addADOperator("__eq", 2,
terra(a: double, b: double)
	return a == b
end)

-- LT
addADOperator("__lt", 2,
terra(a: double, b: double)
	return a < b
end)

-- LE
addADOperator("__le", 2,
terra(a: double, b: double)
	return a <= b
end)

-- GT
addADOperator("__gt", 2,
terra(a: double, b: double)
	return a > b
end)

-- GE
addADOperator("__ge", 2,
terra(a: double, b: double)
	return a >= b
end)


---- Functions ----

-- ACOS
addADFunction("acos", 1,
cmath.acos,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) - v.adj / cmath.sqrt(1.0 - (val(a)*val(a))))
	end
end))

-- ACOSH
addADFunction("acosh", 1,
cmath.acosh,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / cmath.sqrt((val(a)*val(a)) - 1.0))
	end
end))

-- ASIN
addADFunction("asin", 1,
cmath.asin,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / cmath.sqrt(1.0 - (val(a)*val(a))))
	end
end))

-- ASINH
addADFunction("asinh", 1,
cmath.asinh,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / cmath.sqrt((val(a)*val(a)) + 1.0))
	end
end))

-- ATAN
addADFunction("atan", 1,
cmath.atan,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / (1.0 + (val(a)*val(a))))
	end
end))

-- ATAN2
addADFunction("atan2", 2,
cmath.atan2,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, a: T1, b: T2)
		var sqnorm = (val(a)*val(a)) + (val(b)*val(b))
		setadj(a, adj(a) + v.adj * val(b)/sqnorm)
		setadj(b, adj(b) - v.adj * val(a)/sqnorm)
	end
end))

-- CEIL
addADFunction("ceil",
terra(a: num)
	return num(cmath.ceil(a:val()))
end)

-- COS
addADFunction("cos", 1,
cmath.cos,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) - v.adj*cmath.sin(val(a)))
	end
end))

-- COSH
addADFunction("cosh", 1,
cmath.cosh,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj*cmath.sinh(val(a)))
	end
end))

-- EXP
addADFunction("exp", 1,
cmath.exp,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj*v.val)
	end
end))

-- FABS
addADFunction("fabs",
terra(a: num)
	if a:val() >= 0.0 then
		return a
	else
		return -a
	end
end)

-- FLOOR
addADFunction("floor",
terra(a: num)
	return num(cmath.floor(a:val()))
end)

-- FMAX
local terra fmax(a: num, b: double)
	if a:val() >= b then return a else return num(b) end
end
local terra fmax(a: double, b: num)
	if a > b:val() then return num(a) else return b end
end
local terra fmax(a: num, b: num)
	if a:val() > b:val() then return a else return b end
end
addADFunction("fmax", fmax)

-- FMIN
local terra fmin(a: num, b: double)
	if a:val() <= b then return a else return num(b) end
end
local terra fmin(a: double, b: num)
	if a < b:val() then return num(a) else return b end
end
local terra fmin(a: num, b: num)
	if a:val() < b:val() then return a else return b end
end
addADFunction("fmin", fmin)

-- LOG
addADFunction("log", 1,
cmath.log,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / val(a))
	end
end))

-- LOG10
addADFunction("log10", 1,
cmath.log10,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / ([math.log(10.0)]*val(a)))
	end
end))

-- POW
addADFunction("pow", 2,
cmath.pow,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, a: T1, b: T2)
		if val(a) ~= 0.0 then	-- Avoid log(0)
			setadj(a, adj(a) + v.adj*val(b)*v.val/val(a))
			setadj(b, adj(b) + v.adj*cmath.log(val(a))*v.val)
		end
	end
end))

-- ROUND
addADFunction("round",
terra(a: num)
	return num(cmath.round(a:val()))
end)

-- SIN
addADFunction("sin", 1,
cmath.sin,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj*cmath.cos(val(a)))
	end
end))

-- SINH
addADFunction("sinh", 1,
cmath.sinh,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj*cmath.cosh(val(a)))
	end
end))

-- SQRT
addADFunction("sqrt", 1,
cmath.sqrt,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj / (2.0 * v.val))
	end
end))

-- TAN
addADFunction("tan", 1,
cmath.tan,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		setadj(a, adj(a) + v.adj*(1.0 + v.val*v.val))
	end
end))

-- TANH
addADFunction("tanh", 1,
cmath.tanh,
adjoint(function(T)
	return terra(v: &DualNumBase, a: T)
		var c = cmath.cosh(val(a))
		setadj(a, adj(a) + v.adj / (c*c))
	end
end))


-- =============== DERIVATIVE COMPUTATION ===============

-- Recover (but do not free) all memory associated with gradient computation
local terra recoverMemory()
	tape:clear()
	memPool:recoverAll()
end

-- Compute the gradient of the given variable w.r.t all other variables
local terra grad(n: num)
	n.impl.adj = 1.0
	for i=0,tape.size do
		var j = tape.size-i-1
		var tapeEntry = tape:getPointer(j)
		tapeEntry.fn(tapeEntry.datum)
	end
end

-- Compute the gradient of self w.r.t all other variables
-- Until the next call to grad, the adjoints for all other variables
--    will still be correct (though memory has been released for re-use)
terra num:grad()
	grad(@self)
	recoverMemory()
end

-- Compute the gradient of self w.r.t the given vector of
-- variables and store the result in the given vector of doubles
terra num:grad(indeps: &Vector(num), gradient: &Vector(double))
	grad(@self)
	gradient:resize(indeps.size)
	for i=0,indeps.size do
		gradient:set(i, indeps:get(i):adj())
	end
	recoverMemory()
end


-- =============== EXPORTS ===============

return
{
	num = num,
	math = admath,
	recoverMemory = recoverMemory,
	initGlobals = initGlobals
}




