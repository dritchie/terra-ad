
local ad = terralib.require("ad")
local cstdio = terralib.includec("stdio.h")
local Vector = terralib.require("vector")
local m = terralib.require("mem")

local terra test()
	var x = ad.num(1.0)
	var y = ad.num(3.5)
	var z = x - y

	cstdio.printf("x - y: %g\n", z:val())

	z:grad()
	cstdio.printf("dz/dx: %g\n", x:adj())
	cstdio.printf("dz/dy: %g\n", y:adj())

	-- var indeps = [Vector(ad.num)].stackAlloc()
	-- indeps:push(x)
	-- indeps:push(y)
	-- var gradient = [Vector(double)].stackAlloc()
	-- z:grad(&indeps, &gradient)
	-- cstdio.printf("dz/dx: %g\n", gradient:get(0))
	-- cstdio.printf("dz/dy: %g\n", gradient:get(1))
	-- m.destruct(indeps)
	-- m.destruct(gradient)
end

test()