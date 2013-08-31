
CC=clang++
SO=memoryPool.so

HEADERS=\
	memoryPool.h

CPP=\
	memoryPool.cpp

OBJ=$(CPP:.cpp=.o)

all: $(SO)

clean:
	rm -f *.o *.so

$(SO): $(OBJ)
	$(CC) -shared $(OBJ) -o $@

%.o: %.cpp $(HEADERS)
	$(CC) -c -O3 $*.cpp -o $@