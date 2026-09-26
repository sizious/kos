TARGET = bincheck

LIB = libbincheckcore.a
LIB_OBJECTS = check.o scramble.o
OBJECTS = main.o

CC = gcc
AR = ar
STRIP = strip

CFLAGS = -O2 -std=c99 -Wall -Wextra
CPPFLAGS = -I.
LDLIBS = -lm

INSTALLDIR = ..

EXECUTABLEEXTENSION =
ifeq ($(shell echo $(OS)),Windows_NT)
  EXECUTABLEEXTENSION := .exe
endif

OUTPUT = $(TARGET)$(EXECUTABLEEXTENSION)

all: $(OUTPUT)

$(OUTPUT): $(OBJECTS) $(LIB)
	$(CC) $(LDFLAGS) -o $(OUTPUT) $(OBJECTS) $(LIB) $(LDLIBS)
	$(STRIP) $(OUTPUT)

$(LIB): $(LIB_OBJECTS)
	$(AR) rcs $@ $(LIB_OBJECTS)

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

main.o: check.h
check.o: check.h scramble.h
scramble.o: scramble.h

install: $(OUTPUT)
	mkdir -p $(INSTALLDIR)
	mv $(OUTPUT) $(INSTALLDIR)

.PHONY: all install clean
clean:
	-rm -f $(OUTPUT) $(LIB) *.o
