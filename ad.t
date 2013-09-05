local templatize = terralib.require("templatize")
local Vector = terralib.require("vector")
local util = terralib.require("util")

local sourcefile = debug.getinfo(1, "S").source:gsub("@", "")


-- =============== MEMORY POOL ===============

local dir = sourcefile:gsub("ad.t", "")

-- Make sure the memory pool library exists and is up-to-date
io.popen(string.format("cd %s; make -f memoryPool.makefile", dir)):read("*all")

-- Load the header/library
local memoryPoolLib = terralib.includec(sourcefile:gsub("ad.t", "memoryPool.h"))
terralib.linklibrary(sourcefile:gsub("ad.t", "memoryPool.so"))


-- =============== GLOBALS ===============

-- TODO: Make this stuff thread-safe?

-- Global memory pool
local memPool = memoryPoolLib.newPool()

-- Global stack of variables active for the current computation
local VoidPtr = &uint8
local AdjointFn = {&uint8} -> {}
local numStack = terralib.new(Vector(VoidPtr))
Vector(VoidPtr).methods.__construct(numStack)
local fnStack = terralib.new(Vector(AdjointFn))
Vector(AdjointFn).methods.__construct(fnStack)

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
			var dnptr = [&DualNumT](memoryPoolLib.alloc(memPool, sizeof(DualNumT)))
			dnptr.val = val
			dnptr.adj = 0.0
			[makeFieldExpList(dnptr, numExtraFields)] = [args]
			numStack:push([VoidPtr](dnptr))
			fnStack:push(adjFn)
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

local function symbols(types)
	local ret = {}
	for i,t in ipairs(types) do
		table.insert(ret, symbol(t))
	end
	return ret
end

-- This wraps the function created by 'makeADFunction' in a function
-- that expects 'num' in its argument types, instead of &DualNumType
local function wrapADFunction(fn)
	local paramtypes = fn:getdefinitions()[1]:gettype().parameters
	local wrapparams = {}
	local argexps = {}
	for i,t in ipairs(paramtypes) do
		if t == &DualNumBase then
			t = num
		end
		local sym = symbol(t)
		table.insert(wrapparams, sym)
		if t == num then
			table.insert(argexps, `sym.impl)
		else
			table.insert(argexps, sym)
		end
	end
	return terra([wrapparams])
		return fn([argexps])
	end
end

-- This expects to see &DualNumBase in the argTypes
local function makeADFunction(argTypes, usedArgIndices, fwdFn, adjFn)
	local templateTypes = util.index(argTypes, usedArgIndices)
	local DN = DualNum(unpack(templateTypes))
	local params = symbols(argTypes)
	local adjUsedParams = util.index(params, usedArgIndices)
	local paramVals = {}
	for i,prm in ipairs(params) do
		if prm.type == double then
			table.insert(paramVals, prm)
		else
			table.insert(paramVals, `prm.val)
		end
	end
	return terra([params])
		return num { [&DualNumBase](DN.new(fwdFn([paramVals]), adjFn, [adjUsedParams])) }
	end
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
		local adjFn, usedargindices = adjFnTemplate(unpack(types))
		local fn = wrapADFunction(makeADFunction(types, usedargindices, fwdFn, adjFn))
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

local function addADFunction(name, numArgs, fwdFn, adjFnTemplate)
	local primalfn = admath[name]
	if not primalfn then
		error(string.format("ad.t: Cannot add overloaded dual function '%s' for which there is no primal function in cmath", name))
	end
	local dualfn = makeOverloadedADFunction(numArgs, fwdFn, adjFnTemplate)
	for i,def in ipairs(dualfn:getdefinitions()) do
		primalfn:adddefinition(def)
	end
end

local function addADOperator(metamethodname, numArgs, fwdFn, adjFnTemplate)
	local fn = makeOverloadedADFunction(numArgs, fwdFn, adjFnTemplate)
	num.metamethods[metamethodname] = fn
end


-- ADD
addADOperator("__add", 2,
terra(n1: double, n2: double)
	return n1 + n2
end,
adjoint(function(T1, T2)
	return terra(v: &DualNumBase, n1: T1, n2: T2)
		setadj(n1, adj(n1) + v.adj)
		setadj(n2, adj(n2) + v.adj)
	end
end))


-- =============== DERIVATIVE COMPUTATION ===============

-- Recover (but do not free) all memory associated with gradient computation
local terra recoverMemory()
	numStack:clear()
	fnStack:clear()
	memoryPoolLib.recoverAll(memPool)
end

-- Compute the gradient of the given variable w.r.t all other variables
local terra grad(n: num)
	n.impl.adj = 1.0
	for i=0,numStack.size do
		var j = numStack.size-i-1
		fnStack:get(j)(numStack:get(j))
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
	math = admath
}




