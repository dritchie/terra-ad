#ifndef __BENCH_H__
#define __BENCH_H__

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__ ((visibility ("default")))
#endif

#define EXTERN extern "C" {
#ifdef __cplusplus
EXTERN
#endif

EXPORT void forwardSpeedTest_Normal(int outeriters, int inneriters);
EXPORT void forwardSpeedTest_AD(int outeriters, int inneriters);
EXPORT void forwardAndBackwardSpeedTest(int outeriters, int inneriters);

#ifdef __cplusplus
}
#endif

#endif