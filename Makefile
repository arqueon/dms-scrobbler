CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra

.PHONY: all clean

all: mpris-bridge

mpris-bridge: mpris-bridge.c
	$(CC) $(CFLAGS) -o $@ $< -lsystemd -ljson-c

clean:
	rm -f mpris-bridge
