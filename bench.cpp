#include "bench.h"
#include "stan/agrad/agrad.hpp"


template<class T>
void forwardSpeedTest(int outeriters, int inneriters)
{
	for (int i = 0; i < outeriters; i++)
	{
		T res = 0.0;
		for (int j = 0; j < inneriters; j++)
		{
			res += 5.0;
			res -= 5.0;
			res *= 2.0;
			res /= 2.0;
			res = exp(res);
			res = log(res);
		}
		stan::agrad::recover_memory();
	}
}


extern "C"
{
	EXPORT void forwardSpeedTest_Normal(int outeriters, int inneriters)
	{
		forwardSpeedTest<double>(outeriters, inneriters);
	}

	EXPORT void forwardSpeedTest_AD(int outeriters, int inneriters)
	{
		forwardSpeedTest<stan::agrad::var>(outeriters, inneriters);
	}
}