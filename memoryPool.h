#ifndef __MEMORY_POOL_H__
#define __MEMORY_POOL_H__

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__ ((visibility ("default")))
#endif

#define EXTERN extern "C" {
#ifdef __cplusplus
EXTERN
#endif


struct MemoryPool;
typedef struct MemoryPool MemoryPoolT;


EXPORT MemoryPoolT* newPool();
EXPORT void deletePool(MemoryPoolT* pool);
EXPORT void* alloc(MemoryPoolT* pool, unsigned int len);
EXPORT void recoverAll(MemoryPoolT* pool);
EXPORT void freeAll(MemoryPoolT* pool);


#ifdef __cplusplus
}
#endif


#endif