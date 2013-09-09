
-- Re-implementation of stan's "stack_alloc.hpp" in pure Terra to allow for inlining.
-- See STAN_ROOT/src/stan/memory/stack_alloc.hpp for more documentation.

local Vector = terralib.require("vector")
local util = terralib.require("util")
local m = terralib.require("mem")

local C = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
]]


local terra is_aligned(ptr: &int8, bytes_aligned: uint)
	return [uint64](ptr) % bytes_aligned == 0U
end
util.inline(is_aligned)

local DEFAULT_INITIAL_BYTES = 65536		-- 64 KB

local terra eight_byte_aligned_malloc(size: uint) : &int8
	var ptr = [&int8](C.malloc(size))
	if ptr == nil then return ptr end 	-- malloc failed to alloc
	if not is_aligned(ptr, 8U) then
		C.printf("memoryPool.t: invalid alignment to 8 bytes, ptr=%p\n", ptr)
		C.exit(1)
	end
	return ptr
end
util.inline(eight_byte_aligned_malloc)

local struct MemoryPool
{
	blocks_ : Vector(&int8),
	sizes_ : Vector(uint),
	cur_block_ : uint,
	cur_block_end_ : &int8,
	next_loc_ : &int8
}

terra MemoryPool:__construct() : {}
	var initial_nbytes = DEFAULT_INITIAL_BYTES
	self.blocks_ = [Vector(&int8)].stackAlloc(1, eight_byte_aligned_malloc(initial_nbytes))
	self.sizes_ = [Vector(uint)].stackAlloc(1, initial_nbytes)
	self.cur_block_ = 0
	self.cur_block_end_ = self.blocks_:get(0) + initial_nbytes
	self.next_loc_ = self.blocks_:get(0)

	if self.blocks_:get(0) == nil then
		C.printf("memoryPool.t: bad alloc")
		C.exit(1)
	end
end

terra MemoryPool:__destruct()
	-- Free all blocks
	for i=0,self.blocks_.size do
		if self.blocks_:get(i) then
			C.free(self.blocks_:get(i))
		end
	end
	m.destruct(self.blocks_)
	m.destruct(self.sizes_)
end

terra MemoryPool:__move_to_next_block(len: uint)
	var result : &int8
	self.cur_block_ = self.cur_block_ + 1
	-- Find the next block (if any) containing at least len bytes
	while (self.cur_block_ < self.blocks_.size) and
		  (self.sizes_:get(self.cur_block_) < len) do
		  self.cur_block_ = self.cur_block_ + 1
	end
	-- Allocate a new block if necessary
	if self.cur_block_ >= self.blocks_.size then
		var newsize = self.sizes_:back()*2
		if newsize < len then
			newsize = len
		end
		self.blocks_:push(eight_byte_aligned_malloc(newsize))
		if self.blocks_:back() == nil then
			C.printf("memoryPool.t: bad alloc")
			C.exit(1)
		end
		self.sizes_:push(newsize)
	end
	result = self.blocks_:get(self.cur_block_)
	-- Get the object's state back in order.
	self.next_loc_ = result + len
	self.cur_block_end_ = result + self.sizes_:get(self.cur_block_)
	return result
end

terra MemoryPool:alloc(len: uint)
	-- Typically, just return and increment the next location.
	var result = self.next_loc_
	self.next_loc_ = self.next_loc_ + len
	-- Occasionally, we have to switch blocks.
	if self.next_loc_ >= self.cur_block_end_ then
		result = self:__move_to_next_block(len)
	end
	return result
end
util.inline(MemoryPool.methods.alloc)

terra MemoryPool:recoverAll()
	self.cur_block_ = 0
	self.next_loc_ = self.blocks_:get(0)
	self.cur_block_end_ = self.next_loc_ + self.sizes_:get(0)
end
util.inline(MemoryPool.methods.recoverAll)

terra MemoryPool:freeAll()
	-- Free all but the first block
	for i=1,self.blocks_.size do
		if self.blocks_:get(i) then
			C.free(self.blocks_:get(i))
		end
	end
	self.sizes_:resize(1)
	self.blocks_:resize(1)
	self:recoverAll()
end


return MemoryPool







