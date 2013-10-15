#include <vector>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/time.h>
#include "stan/agrad/agrad.hpp"

inline void flush() { fflush(stdout); }
double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

typedef unsigned int uint;

using namespace std;
using namespace stan::agrad;

/////

class Datum
{
public:
	uint label;
	vector<double> features;

	Datum(uint label) : label(label) {}
};

void loadData(const char* filename, uint numToUse, vector<Datum>& data)
{
	data.clear();
	FILE* f = fopen(filename, "r");
	char line[8192];
	bool processedHeader = false;
	uint numDone = 0;
	while (fgets(line, 8192, f))
	{
		if (processedHeader)
		{
			char* tmp = strdup(line);
			char* tok = strtok(tmp, ",");
			int label = atoi(tok);
			Datum datum(label);
			tok = strtok(NULL, ",\n");
			while (tok != NULL and *tok != 0)
			{
				double num = atof(tok);
				datum.features.push_back(num);
				tok = strtok(NULL, ",\n");
			}
			data.push_back(datum);
			free(tmp);
			numDone++;
			printf(" Loading datapoint %u/%u\r", numDone, numToUse);
			flush();
			if (numDone == numToUse)
				break;
		}
		else
		{
			processedHeader = true;
		}
	}
	printf("\n");
	fclose(f);
}

/////

class LogisticRegressionModel
{
public:
	uint numClasses;
	uint numFeatures;
	vector<double> params;

	LogisticRegressionModel(uint numClasses, uint numFeatures)
	: numClasses(numClasses), numFeatures(numFeatures)
	{
		uint numParams = numFeatures * (numClasses+1);
		params.resize(numParams, 0.0);
	}

	inline const var* weights(const vector<var>& params, uint label)
	{
		return &(params[label*(numClasses+1)]);
	}

	inline var bias(const vector<var>& params, uint label)
	{
		return params[label*(numClasses+1) + numClasses];
	}

	var logprob(uint label, const vector<double>& features, const vector<var>& params)
	{
		vector<var> activations(numClasses, 0.0);
		var sumActivations = 0.0;
		for (uint i = 0; i < numClasses; i++)
		{
			const var* w = weights(params, i);
			var dotprod = 0.0;
			for (uint j = 0; j < numFeatures; j++)
				dotprod += w[j]*features[j];
			var act = exp(dotprod + bias(params, i));
			activations[i] = act;
			sumActivations += act;
		}
		return activations[label] / sumActivations;
	}

	void train(const vector<Datum>& data, double learnRate, uint iters)
	{
		vector<var> params(this->params.size(), 0.0);
		vector<double> grad(params.size(), 0.0);
		for (uint iter = 0; iter < iters; iter++)
		{
			printf(" Gradient descent iteration %u/%u\r", iter+1, iters);
			flush();
			for (uint i = 0; i < data.size(); i++)
			{
				for (uint j = 0; j < params.size(); j++)
					params[j] = var(this->params[j]);
				uint label = data[i].label;
				const vector<double>& features = data[i].features;
				var loss = -logprob(label, features, params);
				loss.grad(params, grad);
				for (uint j = 0; j < params.size(); j++)
					this->params[j] += learnRate*grad[j];
			}
		}
		printf("\n");
	}
};

///////////////////////////

// 'train.csv' from https://www.kaggle.com/c/digit-recognizer/data
const char* datafile = "train.csv";
uint numDatapointsToUse = 6000;

// MNIST data has 10 classes (digits 0-10) and images are 28x28
uint numClasses = 10;
uint numFeatures = 28*28;

// Uhhh...some arbitrary constants
double learnRate = 0.05;
uint iters = 100;

int main()
{
	vector<Datum> data;
	loadData(datafile, numDatapointsToUse, data);
	double t0 = CurrentTimeInSeconds();
	LogisticRegressionModel lrm(numClasses, numFeatures);
	lrm.train(data, learnRate, iters);
	double t1 = CurrentTimeInSeconds();
	printf("Time taken: %g\n", t1 - t0);
	// NOTE: This is not a standard stan construct; I added it
	printf("Max tape mem used: %u\n", maxTapeMemUsed());
	return 0;
}









