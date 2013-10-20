
CC=clang++
EXE=mnist

CFLAGS=-I$(STAN_ROOT)/src -I$(STAN_ROOT)/lib/eigen_3.1.2 -I$(STAN_ROOT)/lib/boost_1.53.0

CPP=\
	mnist.cpp \
	$(STAN_ROOT)/src/stan/agrad/rev/var_stack.cpp

OBJ=$(CPP:.cpp=.o)

all: $(EXE)

clean:
	rm -f *.o *.so

$(EXE): $(OBJ)
	$(CC) $(OBJ) -o $@

%.o: %.cpp $(HEADERS)
	#$(CC) -c -O3 $(CFLAGS) $*.cpp -o $@
	$(CC) -c -g -O3 $(CFLAGS) $*.cpp -o $@