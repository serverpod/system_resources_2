OS = $(shell uname -s | tr A-Z a-z)
ARCH = $(shell uname -m | tr A-Z a-z)
CC = gcc # C compiler
CFLAGS = -fPIC -Wall -Wextra -O2 -g # C flags
RM = rm -f # rm command
LDFLAGS = -shared # linking flags
TARGET_LIB := lib/build/libsysres-$(OS)-$(ARCH).so # target lib
SRCS = cpu.c memory.c  # source files
SRCS := $(addprefix lib/src/libsysres/, $(SRCS))
OBJS = $(SRCS:.c=.o)

# Normalize architecture names (Docker uses amd64/arm64, we use x86_64/aarch64)
NORMALIZED_ARCH := $(ARCH)
ifeq ($(ARCH),amd64)
	NORMALIZED_ARCH = x86_64
endif
ifeq ($(ARCH),arm64)
	ifeq ($(OS),linux)
		NORMALIZED_ARCH = aarch64
	else
		NORMALIZED_ARCH = arm64
	endif
endif
ifeq ($(ARCH),i386)
	NORMALIZED_ARCH = i686
endif

ifeq ($(OS),darwin)
	LDFLAGS = -dynamiclib
	TARGET_LIB := lib/build/libsysres-$(OS)-$(NORMALIZED_ARCH).dylib
else
	# Bundle RPATH in Linux builds to avoid need for patchelf
	# $ORIGIN allows libraries to be found relative to the library location
	# Additional paths for common library locations
	LDFLAGS += -Wl,-rpath,'$$ORIGIN:/lib/x86_64-linux-gnu:/lib/aarch64-linux-gnu:/lib64:/lib'
	TARGET_LIB := lib/build/libsysres-$(OS)-$(NORMALIZED_ARCH).so
endif

.PHONY: all
all: ${TARGET_LIB}

$(TARGET_LIB): $(OBJS)
	$(CC) ${LDFLAGS} -o $@ $^

$(SRCS:.c=.d):%.d:%.c
	$(CC) $(CFLAGS) -MM $< >$@

-include $(SRCS:.c=.d)

# Static linking target (requires musl libc for true static linking on glibc systems)
# Note: True static linking on glibc systems is difficult; consider using musl libc
# Usage: make static
# This attempts to statically link system libraries (libc, libm, libpthread)
STATIC_TARGET_LIB := lib/build/libsysres-$(OS)-$(NORMALIZED_ARCH)-static.so
ifeq ($(OS),darwin)
	STATIC_TARGET_LIB := lib/build/libsysres-$(OS)-$(NORMALIZED_ARCH)-static.dylib
endif

.PHONY: static
static:
	@echo "Building statically linked library..."
	@echo "Note: On glibc systems, true static linking may require musl libc toolchain"
ifeq ($(OS),darwin)
	$(CC) $(CFLAGS) -dynamiclib -o $(STATIC_TARGET_LIB) $(OBJS) -static-libgcc
else
	# Attempt static linking (may fail on glibc systems - use musl for true static)
	$(CC) $(CFLAGS) -shared -o $(STATIC_TARGET_LIB) $(OBJS) -static-libgcc -Wl,-Bstatic -lc -lm -lpthread -Wl,-Bdynamic || \
	(echo "Warning: Static linking failed. Try using musl libc: CC=musl-gcc make static" && exit 1)
endif
	@echo "Static library built: $(STATIC_TARGET_LIB)"

.PHONY: clean
clean:
	-${RM} ${OBJS} $(SRCS:.c=.d)

fclean: clean
	-${RM} ${TARGET_LIB} lib/build/libsysres-*-static.*
