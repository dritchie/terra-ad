
local ad = terralib.require("ad")

C = terralib.includecstring [[
	#include <stdio.h>
	#include <stdlib.h>
	#include <math.h>
	#include <sys/time.h>
	double CurrentTimeInSeconds() {
	    struct timeval tv;
	    gettimeofday(&tv, NULL);
	    return tv.tv_sec + tv.tv_usec / 1000000.0;
	}
]]

local str = &int8
local TestFn = {} -> {}

-- Benchmarks for automatic differentiation

local cppbench = terralib.includec("bench.h")
terralib.linklibrary("libbench.so")

local terra doTest_inner(name: str, fn: TestFn)
	C.printf("TEST: %s - ", name)
	var t0 = C.CurrentTimeInSeconds()
	fn()
	var t1 = C.CurrentTimeInSeconds()
	C.printf("%g\n", t1-t0)
end

local function doTest(name, fn)
	doTest_inner(name, fn:getdefinitions()[1]:getpointer())
end

local forward_numOuterIterations = 10000
local forward_numInnerIterations = 1000
local function makeForwardSpeedTest(T)
	return terra()
		for i=0,forward_numOuterIterations do
			var res = T(1.0)
			for j=0,forward_numInnerIterations do
				res = res + 5.0
				res = res - 5.0
				res = res * 2.0
				res = res / 2.0
				res = ad.math.exp(res)
				res = ad.math.log(res)
			end
			ad.recoverMemory()
		end
	end
end

doTest("Foward Speed Test (Terra, Normal)", makeForwardSpeedTest(double))
doTest("Foward Speed Test (Terra, AD)", makeForwardSpeedTest(ad.num))

local function makeCPPForwardSpeedTest(cppfn)
	return terra()
		cppfn(forward_numOuterIterations, forward_numInnerIterations)
	end
end

doTest("Foward Speed Test (C++, Normal)", makeCPPForwardSpeedTest(cppbench.forwardSpeedTest_Normal))
doTest("Foward Speed Test (C++, AD)", makeCPPForwardSpeedTest(cppbench.forwardSpeedTest_AD))