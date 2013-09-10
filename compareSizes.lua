

local util = terralib.require("util")

local function getLineCount(filename)
	return tonumber(util.wait(string.format("wc %s", filename)):split(" ")[1])
end

local function getStanFileLineCount(filename)
	local fullfilename = string.format("$STAN_ROOT/src/stan/agrad/rev/%s", filename)
	util.wait(string.format("python decomment.py %s decomment_tmp cpp", fullfilename))
	local lc = getLineCount("decomment_tmp")
	util.wait("rm -f decomment_tmp")
	return lc
end

local function getTerraFileLineCount(filename)
	util.wait(string.format("python decomment.py %s decomment_tmp lua", filename))
	local lc = getLineCount("decomment_tmp")
	util.wait("rm -f decomment_tmp")
	return lc
end

-- Size of Terra AD code
print(string.format("Terra AD line count: %d", getTerraFileLineCount("ad.t")))

print("----------")

-- Size of Stan AD code
local basefilenames = 
{
	"chainable.hpp",
	"vari.hpp",
	"var_stack.hpp",
	"op/v_vari.hpp",
	"op/dv_vari.hpp",
	"op/vd_vari.hpp",
	"op/vv_vari.hpp",
	"op/vvv_vari.hpp",
	"op/vvd_vari.hpp",
	"op/vdv_vari.hpp",
	"op/vdd_vari.hpp",
	"op/dvv_vari.hpp",
	"op/dvd_vari.hpp",
	"op/ddv_vari.hpp"
}
local opfilenames = 
{
	"operator_addition.hpp",
	"operator_subtraction.hpp",
	"operator_multiplication.hpp",
	"operator_division.hpp",
	"operator_unary_negative.hpp",
	"operator_equal.hpp",
	"operator_less_than.hpp",
	"operator_less_than_or_equal.hpp",
	"operator_greater_than.hpp",
	"operator_greater_than_or_equal.hpp",
	"acos.hpp",
	"acosh.hpp",
	"asin.hpp",
	"asinh.hpp",
	"atan.hpp",
	"atan2.hpp",
	"ceil.hpp",
	"cos.hpp",
	"cosh.hpp",
	"exp.hpp",
	"fabs.hpp",
	"floor.hpp",
	"fmax.hpp",
	"fmin.hpp",
	"log.hpp",
	"log10.hpp",
	"pow.hpp",
	"round.hpp",
	"sin.hpp",
	"sinh.hpp",
	"sqrt.hpp",
	"tan.hpp",
	"tanh.hpp"
}
local unaryExample = "sqrt.hpp"
local binaryExample = "pow.hpp"
local baseCodeLineCount = 0
for i,f in ipairs(basefilenames) do
	baseCodeLineCount = baseCodeLineCount + getStanFileLineCount(f)
end
local opsLineCount = 0
for i,f in ipairs(opfilenames) do
	opsLineCount = opsLineCount + getStanFileLineCount(f)
end
print(string.format("stan AD base code line count: %d", baseCodeLineCount))
print(string.format("stan AD op code line count: %d", opsLineCount))
print(string.format("stan AD total line count: %d", baseCodeLineCount + opsLineCount))
print(string.format("stan incremental unary op line count: ~%d", getStanFileLineCount(unaryExample)))
print(string.format("stan incremental binary op line count: ~%d", getStanFileLineCount(binaryExample)))