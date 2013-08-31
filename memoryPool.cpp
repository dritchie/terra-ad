#include "memoryPool.h"
#include "stack_alloc.hpp"

struct MemoryPool
{
	stan::memory::stack_alloc allocator;
};

extern "C"
{
	EXPORT MemoryPool* newPool()
	{
		MemoryPool* pool = new MemoryPool;
		return pool;
	}

	EXPORT void deletePool(MemoryPool* pool)
	{
		delete pool;
	}

	EXPORT void* alloc(MemoryPool* pool, unsigned int len)
	{
		return pool->allocator.alloc(len);
	}

	EXPORT void recoverAll(MemoryPool* pool)
	{
		pool->allocator.recover_all();
	}

	EXPORT void freeAll(MemoryPool* pool)
	{
		pool->allocator.free_all();
	}
}