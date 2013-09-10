

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

-- Size of Stan AD code
local filenames = 
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
local unaryExample = "sqrt.hpp"
local binaryExample = "pow.hpp"
local baseCodeLineCount = 0
for i,f in ipairs(filenames) do
	baseCodeLineCount = baseCodeLineCount + getStanFileLineCount(f)
end
print(string.format("stan AD base code line count: %d", baseCodeLineCount))
print(string.format("stan additional unary op line count: ~%d", getStanFileLineCount(unaryExample)))
print(string.format("stan additional binary op line count: ~%d", getStanFileLineCount(binaryExample)))