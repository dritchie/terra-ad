
CC=clang++
SO=libbench.so

CFLAGS=-I$(STAN_ROOT)/src -I$(STAN_ROOT)/lib/eigen_3.1.2 -I$(STAN_ROOT)/lib/boost_1.53.0

HEADERS=\
	bench.h

CPP=\
	bench.cpp \
	$(STAN_ROOT)/src/stan/agrad/rev/var_stack.cpp

OBJ=$(CPP:.cpp=.o)

all: $(SO)

clean:
	rm -f *.o *.so

$(SO): $(OBJ)
	$(CC) -shared $(OBJ) -o $@

%.o: %.cpp $(HEADERS)
	$(CC) -c -O3 $(CFLAGS) $*.cpp -o $@