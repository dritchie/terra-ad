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
Vector(VoidPtr).methods.construct(numStack)
local fnStack = terralib.new(Vector(AdjointFn))
Vector(AdjointFn).methods.construct(fnStack)


-- =============== DUAL NUMBER TYPE GENERATION ===============

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
		table.insert(DualNum.entries, select(i,...))
	end

	-- All dual nums are allocated from the memory pool
	DualNumT.methods.new = macro(function(val, adjFn, ...)
		local args = {}
		for i=1,numExtraFields do
			table.insert(args, select(i, ...))
		end
		local function makeFields(obj)
			local fields = {}
			for i=1,numExtraFields do
				table.insert(fields, `obj.[string.format("_%d", i-1)])
			end
			return fields
		end
		return quote
			local dnptr = [&DualNumT](memoryPoolLib.alloc(memPool, sizeof(DualNumT)))
			dnptr.val = val
			dnptr.adj = 0.0
			[makeFields(dnptr)] = [args]
			numStack:push(dnptr)
			fnStack:push(adjFn)
		in
			dnptr
		end
	end

	return DualNumT
end)
local DualNumBase = DualNum()

-- The externally-visible dual number type
local struct num
{
	impl: &DualNumBase
}

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
			t = number
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
local function makeADFunction(argTypes, fwdFn, adjFun)
	local params = symbols(argTypes)
	local DN = DualNum(argTypes)
	return terra([params])
		var newnum = num { DN.new(fwdFn([params]), [params]) }
		return newnum
	end
end

local function makeOverloadedADFunction(numArgs, fwdFnTemplate, adjFnTemplate)
	local overallfn = nil
	local numVariants = 2 ^ numArgs
	local bitstring = 1
	for i=1,numVariants-1 do
		local types = {}
		for j=1,numArgs do
			if bit.band(bit.tobit(2^j), bit.tobit(bitstring)) == 0 then
				table.insert(types, double)
			else
				table.insert(types, &DualNumBase)
		end
		local fn = wrapADFunction(makeADFunction(types, fwdFnTemplate(types), adjFnTemplate(types)))
		if not overallfn then
			overallfn = fn
		else
			overallfn:adddefinition(fn:getdefinitions()[1])
		end
		bitstring = bitstring + 1
	end
	return overallfn
end


-- =============== INSTANTIATE ALL THE FUNCTIONS! ===============

local admath = util.copytable(cmath)

local function addADFunction(name, numArgs, fwdFnTemplate, adjFnTemplate)
	local primalfn = admath[name]
	if not primalfn then
		error(string.format("ad.t: Cannot add overloaded dual function '%s' for which there is no primal function in cmath", name))
	end
	local dualfn = makeOverloadedADFunction(numArgs, fwdFnTemplate, adjFnTemplate)
	for i,def in ipairs(dualfn:getdefinitions()) do
		primalfn:adddefinition(def)
	end
end

local function addADOperator(metamethodname, numArgs, fwdFnTemplate, adjFnTemplate)
	local fn = makeOverloadedADFunction(numArgs, fwdFn, adjFnTemplate)
	num.metamethods[metamethodname] = fn
end

-- Extract the numeric value from a number regardless of whether
-- it is a double or a dual number
local val = macro(function(v)
	if v:gettype() == double then
		return v
	else
		return `v.val
	end
end)


-- -- ADD
-- addADOperator("__add", 2,
-- function(types)
-- 	return terra(n1: types[1], n2: types[2])
-- 		return val(n1) + val(n2)
-- 	end
-- end,
-- function(types)
-- 	local DN = DualNum(types)
-- 	return terra(impl: VoidPtr)
-- 		--
-- 	end
-- end)







