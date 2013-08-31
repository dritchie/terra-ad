local templatize = terralib.require("templatize")
local Vector = terralib.require("vector")

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
	DualNumT.methods.new = macro(function(val, ...)
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

num.metamethods.__cast = function(from, to, exp)
	if from == double and to == num then
		-- TEMP NOTE: Even base DualNums need an adjoint function
		-- (the empty function). I think pushing to the stack needs
		-- to be handled in DualNum.new, somehow...?
		return `num { DualNumBase.new(exp) }
	else
		error(string.format("ad.t: Cannot cast '%s' to 'num'", tostring(from)))
	end
end


-- =============== FUNCTION GENERATION ===============

local cmath = terralib.includec("math.h")

-- TEMP NOTE: This wraps the below function in a function
-- that expects num in its arguments. It'll unpack the
-- nums into their impls before calling the wrapped function.
local function wrapADFunction(fn, args)
	local params = fn:getdefinitions()[1]:gettype().parameters
	-- ???
end

-- TEMP NOTE: This expects to see &DualNumBase in the argTypes
local function makeADFunction(argTypes, fwdFn, adjFun)
	local params = {}
	for i,t in ipairs(argTypes) do
		table.insert(params, symbol(t))
	end
	local DN = DualNum(argTypes)
	return terra([params])
		-- TEMP NOTE: This line is wrong; we need to be using the
		-- DN type!
		var newnum = num(fwdFn([params]))
		numStack:push(newnum.impl)
		fnStack:push(adjFun)
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
		local fn = makeADFunction(types, fwdFnTemplate(types), adjFnTemplate(types))
		if not overallfn then
			overallfn = fn
		else
			overallfn:adddefinition(fn:getdefinitions()[1])
		end
		bitstring = bitstring + 1
	end
	return overallfn
end







