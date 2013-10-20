local Vector = terralib.require("vector")
local ad = terralib.require("ad")
local num = ad.num
local m = terralib.require("mem")
local util = terralib.require("util")

local C = terralib.includecstring [[
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/time.h>
inline void flush() { fflush(stdout); }
double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}
]]

local struct Datum
{
	label: uint,
	features: Vector(double)
}

terra Datum:__construct(label: uint)
	self.label = label
	m.init(self.features)
end

terra Datum:__construct(label: uint, features: &Vector(double))
	self.label = label
	self.features = m.copy(@features)
end

terra Datum:__destruct()
	m.destruct(self.features)
end

m.addConstructors(Datum)

-----

-- NOTE: Caller assumes ownership of returned vector
local terra loadData(filename: rawstring, numToUse: uint)
	var data = [Vector(Datum)].stackAlloc()
	var f = C.fopen(filename, "r")
	var line : int8[8192]
	var processedHeader = false
	var numDone = 0U
	while C.fgets(line, 8192, f) ~= nil do
		if processedHeader then
			var tmp = C.strdup(line)
			var tok = C.strtok(tmp, ",")
			var label = C.atoi(tok)
			var datum = Datum.stackAlloc(label)
			tok = C.strtok(nil, ",\n")
			while tok ~= nil and @tok ~= 0 do
				var num = C.atof(tok)
				datum.features:push(num/255)
				tok = C.strtok(nil, ",\n")
			end
			data:push(datum)
			C.free(tmp)
			numDone = numDone + 1
			C.printf(" Loading datapoint %u/%u\r", numDone, numToUse)
			C.flush()
			if numDone == numToUse then break end
		else
			processedHeader = true
		end
	end
	C.printf("\n")
	C.fclose(f)
	return data
end

-----

local struct LogisticRegressionModel
{
	numClasses: uint,
	numFeatures: uint,
	params: Vector(double)
}

terra LogisticRegressionModel:__construct(numClasses: uint, numFeatures: uint)
	self.numClasses = numClasses
	self.numFeatures = numFeatures
	var numParams = numFeatures*(numClasses+1)
	self.params = [Vector(double)].stackAlloc(numParams, 0.0)
end

terra LogisticRegressionModel:__destruct()
	m.destruct(self.params)
end

terra LogisticRegressionModel:weights(params: &Vector(num), class: uint)
	return params:getPointer(class*(self.numClasses+1))
end
util.inline(LogisticRegressionModel.methods.weights)

terra LogisticRegressionModel:bias(params: &Vector(num), class: uint)
	return params:get(class*(self.numClasses+1) + self.numClasses)
end
util.inline(LogisticRegressionModel.methods.bias)

terra LogisticRegressionModel:logprob(class: int, features: &Vector(double), params: &Vector(num))
	var activations = [Vector(num)].stackAlloc(self.numClasses, 0.0)
	var sumActivations = num(0.0)
	for i=0,self.numClasses do
		var w = self:weights(params, i)
		var dotprod = num(0.0)
		for j=0,self.numFeatures do
			dotprod = dotprod + w[j]*features:get(j)
		end
		var act = ad.math.exp(dotprod + self:bias(params, i))
		activations:set(i, act)
		sumActivations = sumActivations + act
	end
	var ret = activations:get(class) / sumActivations
	m.destruct(activations)
	return ad.math.log(ret)
end

-- Gradient descent
terra LogisticRegressionModel:train(data: &Vector(Datum), learnRate: double, iters: uint)
	var params = [Vector(num)].stackAlloc(self.params.size, 0.0)
	var grad = [Vector(double)].stackAlloc(self.params.size, 0.0)
	for iter=0,iters do
		var loss = num(0.0)
		for j=0,self.params.size do
			params:set(j, num(self.params:get(j)))
		end
		for i=0,data.size do
			var class = data:getPointer(i).label
			var features = &(data:getPointer(i).features)
			loss = loss - self:logprob(class, features, &params)
		end
		C.printf(" Gradient descent iteration %u/%u (loss = %g)     \r", iter+1, iters, loss:val())
		C.flush()
		loss:grad(&params, &grad)
		for j=0,self.params.size do
			self.params:set(j, self.params:get(j) - learnRate*grad:get(j))
		end
	end
	C.printf("\n")
	m.destruct(params)
	m.destruct(grad)
end

m.addConstructors(LogisticRegressionModel)


-----------------------------------

-- 'train.csv' from https://www.kaggle.com/c/digit-recognizer/data
local datafile = "/Users/dritchie/Git/terra-ad/mnist/train.csv"
local numDatapointsToUse = 6000

-- MNIST data has 10 classes (digits 0-10) and images are 28x28
local numClasses = 10
local numFeatures = 28*28

-- Uhhh...some arbitrary constants
local learnRate = 0.00005
local iters = 100

local terra doTraining()
	var data = loadData(datafile, numDatapointsToUse)
	var t0 = C.CurrentTimeInSeconds()
	var lrm = LogisticRegressionModel.stackAlloc(numClasses, numFeatures)
	lrm:train(&data, learnRate, iters)
	var t1 = C.CurrentTimeInSeconds()
	var paramsum = 0.0
	for i=0,lrm.params.size do
		paramsum = paramsum + lrm.params:get(i)
	end
	m.destruct(lrm)
	m.destruct(data)
	C.printf("Sum of learned params: %g\n", paramsum)
	C.printf("Time taken: %g\n", t1 - t0)
	C.printf("Max tape mem used: %u\n", ad.maxTapeMemUsed())
end

--doTraining()
terralib.saveobj("mnist_terra",
{
	main = terra()
		ad.initGlobals()
		doTraining()
	end
})











