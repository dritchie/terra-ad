-- Here's the gist:
-- * fastexp is no faster than normal exp
-- * fastpow is about 4.5x faster than normal pow, but only when the exponent is non-constant.
--   When the exponent is compile-time constant, as in my intended softmin use case, the two
--   have the same performance.



-- local terra fastexp(val: double)
-- 	var tmp = [int64](1512775 * val + (1072693248 - 60801)) << 32
-- 	var ptr = [&double](&tmp)
-- 	return @ptr
-- end

local terra fastpow(a: double, b: double)
	var tmp = @([&int64](&a)) >> 32
	var tmp2 = [int64](b * (tmp - 1072632447) + 1072632447) << 32
	var ptr = [&double](&tmp2)
	return @ptr
end


local ad = require("ad")
local Vector = require("vector")

local C = terralib.includecstring [[
#include <stdio.h>
#include <sys/time.h>
inline void flush() { fflush(stdout); }
double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}
]]

local function runPowTest(fn)
	print(string.format("%s: ", fn.name))
	local terra test()
		var t0 = C.CurrentTimeInSeconds()
		var vals = Vector.fromItems(1.0, -0.4, -3.5, 0.2, 1.7)
		var total = 0.0
		for i=0,100000000 do
			for j=0,vals.size do
				total = total + fn(vals:get(j), vals:get(j))
			end
		end
		var t1 = C.CurrentTimeInSeconds()
		C.printf("%g seconds\n", t1-t0)
		return total
	end
	test()
end

runPowTest(ad.math.pow)
runPowTest(fastpow)

-- return `ad.math.pow(ad.math.pow([ce], -power) + ad.math.pow(maxval, -power), 1.0/-power)

local function softmin(powfn)
	return terra(x1: double, x2: double, a: double)
		return powfn(powfn(x1, -a) + powfn(x2, -a), 1.0/-a)
	end
end

-- print(softmin(ad.math.pow)(1.5, 1.0, 20))
-- print(softmin(fastpow)(1.5, 1.0, 20))


local function runSoftminTest(fn)
	print(string.format("%s: ", fn.name))
	local terra test()
		var t0 = C.CurrentTimeInSeconds()
		var vals = Vector.fromItems(1.0, 1.4, 3.5, 2.2, 4.7)
		var total = 0.0
		for i=0,100000000 do
			for j=0,vals.size do
				total = total + fn(vals:get(j), 1.0, vals:get(j))
			end
		end
		var t1 = C.CurrentTimeInSeconds()
		C.printf("%g seconds\n", t1-t0)
		return total
	end
	test()
end

-- runSoftminTest(softmin(ad.math.pow))
-- runSoftminTest(softmin(fastpow))

