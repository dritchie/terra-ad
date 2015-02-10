
local ad = require("ad")
local cstdio = terralib.includec("stdio.h")
local cmath = terralib.includec("math.h")
local Vector = require("vector")
local util = require("util")
local m = require("mem")

local num = ad.num
local str = &int8
local Array = Vector.fromItems

local numtests = global(int, 0)
local numtestspassed = global(int, 0)
local errthresh = 0.0000001
local terra eqtest(val: double, trueval: double)
	numtests = numtests + 1
	if cmath.fabs(val - trueval) < errthresh then
		numtestspassed = numtestspassed + 1
		cstdio.printf("PASSED.\n")
	else
		cstdio.printf("failed! (got %g, expected %g)\n", val, trueval)
	end
end

local terra gradtest(name: str, dep: num, trueval: double, indeps: Vector(num), truegrad: Vector(double))
	cstdio.printf("TEST %s\n", name)
	dep:grad()
	cstdio.printf("   Value: ")
	eqtest(dep:val(), trueval)
	for i=0,indeps.size do
		cstdio.printf("   Derivative %d: ", i)
		eqtest(indeps:get(i):adj(), truegrad:get(i))
	end
	m.destruct(indeps)
	m.destruct(truegrad)
end

local function runTestIf(testModule, condition)
	if condition then
		local test = testModule()
		test()
	end
end

-------------------------------------------------

runTestIf(function()
	return terra()
		var x = ad.num(1.0)
		var y = ad.num(3.5)
		var z = x + y
		gradtest("add operator", z, 4.5,
				 Array(x, y),
				 Array(1.0, 1.0))
	end
end,
true)

runTestIf(function()
		return terra()
		var x = ad.num(1.0)
		var y = ad.num(3.5)
		var z = x - y
		gradtest("sub operator", z, -2.5,
				 Array(x, y),
				 Array(1.0, -1.0))
	end
end,
true)

runTestIf(function()
	return terra()
		var x = ad.num(2.0)
		var y = ad.num(5.0)
		var z = x * y
		gradtest("mul operator", z, 10.0,
				 Array(x, y),
				 Array(1.0*5.0 + 2.0*0.0, 0.0*5.0 + 2.0*1.0))
	end
end,
true)

runTestIf(function()
	return terra()
		var x = ad.num(10.0)
		var y = ad.num(2.0)
		var z = x / y
		gradtest("div operator", z, 5.0,
				 Array(x, y),
				 Array((1.0*2.0 - 10.0*0.0)/(2.0*2.0),
				 		(0.0*2.0 - 10.0*1.0)/(2.0*2.0)))
	end
end,
true)

runTestIf(function()
	return terra()
		var x = ad.num(0.5)
		var z = ad.math.acos(x)
		gradtest("acos function", z, cmath.acos(0.5),
				 Array(x),
				 Array(-1.0/cmath.sqrt(1.0-0.5*0.5)))
	end
end,
ad.math.acos)

runTestIf(function()
	return terra()
		var x = ad.num(1.4)
		var z = ad.math.acosh(x)
		gradtest("acosh function", z, cmath.acosh(1.4),
				 Array(x),
				 Array(1.0/cmath.sqrt(1.4*1.4-1.0)))
	end
end,
ad.math.acosh)

runTestIf(function()
	return terra()
		var x = ad.num(0.7)
		var z = ad.math.asin(x)
		gradtest("asin function", z, cmath.asin(0.7),
				 Array(x),
				 Array(1.0/cmath.sqrt(1.0-0.7*0.7)))
	end
end,
ad.math.asin)

runTestIf(function()
	return terra()
		var x = ad.num(-0.3)
		var z = ad.math.asinh(x)
		gradtest("asinh function", z, cmath.asinh(-0.3),
				 Array(x),
				 Array(1.0/cmath.sqrt(0.3*0.3+1.0)))
	end
end,
ad.math.asinh)

runTestIf(function()
	return terra()
		var x = ad.num(0.22)
		var z = ad.math.atan(x)
		gradtest("atan function", z, cmath.atan(0.22),
				 Array(x),
				 Array(1.0/(1.0+0.22*0.22)))
	end
end,
ad.math.atan)

-- TODO: Test for atan2 (got lazy; didn't want to do calculus...)

runTestIf(function()
	return terra()
		var x = ad.num(1.1)
		var z = ad.math.cos(x)
		gradtest("cos function", z, cmath.cos(1.1),
				 Array(x),
				 Array(-cmath.sin(1.1)))
	end
end,
ad.math.cos)

runTestIf(function()
	return terra()
		var x = ad.num(-0.9)
		var z = ad.math.cosh(x)
		gradtest("cosh function", z, cmath.cosh(-0.9),
				 Array(x),
				 Array(cmath.sinh(-0.9)))
	end
end,
ad.math.cosh)

runTestIf(function()
	return terra()
		var x = ad.num(0.6)
		var z = ad.math.exp(x)
		gradtest("exp function", z, cmath.exp(0.6),
				 Array(x),
				 Array(cmath.exp(0.6)))
	end
end,
ad.math.exp)

runTestIf(function()
	return terra()
		var x = ad.num(2.0)
		var y = ad.num(5.0)
		var z = ad.math.fmax(x, y)
		gradtest("fmax function (1)", z, 5.0,
				 Array(x, y),
				 Array(0.0, 1.0))
	end
end,
ad.math.fmax)

runTestIf(function()
	return terra()
		var x = ad.num(8.0)
		var y = ad.num(5.0)
		var z = ad.math.fmax(x, y)
		gradtest("fmax function (2)", z, 8.0,
				 Array(x, y),
				 Array(1.0, 0.0))
	end
end,
ad.math.fmax)

runTestIf(function()
	return terra()
		var x = 2.0
		var y = ad.num(5.0)
		var z = ad.math.fmax(x, y)
		gradtest("fmax function (3)", z, 5.0,
				 Array(y),
				 Array(1.0))
	end
end,
ad.math.fmax)

runTestIf(function()
	return terra()
		var x = 8.0
		var y = ad.num(5.0)
		var z = ad.math.fmax(x, y)
		gradtest("fmax function (4)", z, 8.0,
				 Array(y),
				 Array(0.0))
	end
end,
ad.math.fmax)

runTestIf(function()
	return terra()
		var x = ad.num(2.0)
		var y = ad.num(5.0)
		var z = ad.math.fmin(x, y)
		gradtest("fmin function (1)", z, 2.0,
				 Array(x, y),
				 Array(1.0, 0.0))
	end
end,
ad.math.fmin)

runTestIf(function()
	return terra()
		var x = ad.num(8.0)
		var y = ad.num(5.0)
		var z = ad.math.fmin(x, y)
		gradtest("fmin function (2)", z, 5.0,
				 Array(x, y),
				 Array(0.0, 1.0))
	end
end,
ad.math.fmin)

runTestIf(function()
	return terra()
		var x = 2.0
		var y = ad.num(5.0)
		var z = ad.math.fmin(x, y)
		gradtest("fmin function (3)", z, 2.0,
				 Array(y),
				 Array(0.0))
	end
end,
ad.math.fmin)

runTestIf(function()
	return terra()
		var x = 8.0
		var y = ad.num(5.0)
		var z = ad.math.fmin(x, y)
		gradtest("fmin function (4)", z, 5.0,
				 Array(y),
				 Array(1.0))
	end
end,
ad.math.fmin)

runTestIf(function()
	return terra()
		var x = ad.num(30.24)
		var z = ad.math.log(x)
		gradtest("log function", z, cmath.log(30.24),
				 Array(x),
				 Array(1.0/30.24))
	end
end,
ad.math.log)

runTestIf(function()
	return terra()
		var x = ad.num(89.11)
		var z = ad.math.log10(x)
		gradtest("log10 function", z, cmath.log10(89.11),
				 Array(x),
				 Array(1.0/(89.11*cmath.log(10))))
	end
end,
ad.math.log10)

runTestIf(function()
	return terra()
		var x = ad.num(2.3)
		var y = ad.num(-4.2)
		var z = ad.math.pow(x, y)
		gradtest("pow function", z, cmath.pow(2.3, -4.2),
				 Array(x, y),
				 Array(-4.2*cmath.pow(2.3, -5.2), cmath.pow(2.3, -4.2)*cmath.log(2.3)))
	end
end,
ad.math.pow)

runTestIf(function()
	return terra()
		var x = ad.num(1.1)
		var z = ad.math.sin(x)
		gradtest("sin function", z, cmath.sin(1.1),
				 Array(x),
				 Array(cmath.cos(1.1)))
	end
end,
ad.math.sin)

runTestIf(function()
	return terra()
		var x = ad.num(-0.9)
		var z = ad.math.sinh(x)
		gradtest("sinh function", z, cmath.sinh(-0.9),
				 Array(x),
				 Array(cmath.cosh(-0.9)))
	end
end,
ad.math.sinh)

runTestIf(function()
	return terra()
		var x = ad.num(123.52)
		var z = ad.math.sqrt(x)
		gradtest("sqrt function", z, cmath.sqrt(123.52),
				 Array(x),
				 Array(1.0/(2.0*cmath.sqrt(123.52))))
	end
end,
ad.math.sqrt)

runTestIf(function()
	return terra()
		var x = ad.num(1.1)
		var z = ad.math.tan(x)
		gradtest("tan function", z, cmath.tan(1.1),
				 Array(x),
				 Array(1.0 + cmath.tan(1.1)*cmath.tan(1.1)))
	end
end,
ad.math.tan)

runTestIf(function()
	return terra()
		var x = ad.num(-0.9)
		var z = ad.math.tanh(x)
		gradtest("tanh function", z, cmath.tanh(-0.9),
				 Array(x),
				 Array(1.0/(cmath.cosh(-0.9)*cmath.cosh(-0.9))))
	end
end,
ad.math.tanh)


print()
print(string.format("Passed %d/%d tests.", numtestspassed:get(), numtests:get()))




