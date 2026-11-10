# Windows x64 build for the native WinDivert backend (MSYS2 UCRT64 or MinGW-w64 cross compiler).
# Run from this directory (or use: make -C windows/src ...).
ifndef MSYSTEM
CPREFIX ?= x86_64-w64-mingw32-
endif

WINDIVERT_DIR ?= ../deps/WinDivert-2.2.2-A
WINDIVERTHEADERS ?= $(WINDIVERT_DIR)/include
WINDIVERTLIBS ?= $(WINDIVERT_DIR)/x64

TARGET = goodbyedpi.exe
BIT64 ?= 1
LIBS = -L$(WINDIVERTLIBS) -lWinDivert -lws2_32
CC = $(CPREFIX)gcc

CCWINDRES = $(CPREFIX)windres
ifeq (, $(shell command -v $(CCWINDRES) 2>/dev/null))
	CCWINDRES = windres
endif

CFLAGS = -std=c99 -pie -fPIE -pipe -isystem $(WINDIVERTHEADERS) -L$(WINDIVERTLIBS) \
         -O2 -D_FORTIFY_SOURCE=2 -fstack-protector \
         -Wall -Wextra -Wpedantic -Wformat=2 -Wformat-overflow=2 -Wformat-truncation=2 \
         -Wformat-security -Wno-format-nonliteral -Wshadow -Wstrict-aliasing=1 \
         -Wnull-dereference -Warray-bounds=2 -Wimplicit-fallthrough=3 \
         -Wstringop-overflow=4 -Wformat-signedness -Wstrict-overflow=2 \
         -Wcast-align=strict -Wfloat-equal -Wsign-conversion

LDFLAGS = -fstack-protector -Wl,-O1,-pie,--dynamicbase,--nxcompat,--sort-common,--as-needed \
          -Wl,--disable-auto-image-base

ifdef BIT64
	LDFLAGS += -Wl,--high-entropy-va -Wl,--pic-executable,-e,mainCRTStartup
else
$(error This repository currently builds Windows x64 only. Use BIT64=1.)
endif

.PHONY: all clean
all: $(TARGET)

OBJECTS = $(patsubst %.c, %.o, $(wildcard *.c utils/*.c)) goodbyedpi-rc.o
HEADERS = $(wildcard *.h utils/*.h)

%.o: %.c $(HEADERS)
	$(CC) $(CFLAGS) -c $< -o $@

goodbyedpi-rc.o: goodbyedpi-rc.rc goodbyedpi.exe.manifest icon.ico
	$(CCWINDRES) goodbyedpi-rc.rc goodbyedpi-rc.o

$(TARGET): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) $(LIBS) -s -o $@

clean:
	-rm -f *.o utils/*.o
	-rm -f $(TARGET)
