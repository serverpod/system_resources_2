CC = gcc # C compiler
CFLAGS = -fPIC -Wall -Wextra -O2 -g # C flags
RM = rm -f # rm command
LDFLAGS = -shared # linking flags

# Detect OS using GCC predefined macros (no external binaries required)
OS := $(shell echo | $(CC) -dM -E - | grep -q __APPLE__ && echo darwin || echo linux)

# Detect ARCH using GCC predefined macros
ARCH := $(shell echo | $(CC) -dM -E - | grep -q __aarch64__ && echo aarch64 || \
        (echo | $(CC) -dM -E - | grep -q __x86_64__ && echo x86_64 || \
        (echo | $(CC) -dM -E - | grep -q __arm__ && echo armv7l || echo i686)))

# Normalize ARCH for macOS (uses arm64 not aarch64)
ifeq ($(OS),darwin)
  ifeq ($(ARCH),aarch64)
    ARCH := arm64
  endif
endif

# Directories
SRC_DIR := lib/src/libsysres
BUILD_DIR := lib/build/obj/$(OS)-$(ARCH)

# Target library
TARGET_LIB := lib/build/libsysres-$(OS)-$(ARCH).so

# Source files
SRC_FILES = cpu.c memory.c
SRCS := $(addprefix $(SRC_DIR)/, $(SRC_FILES))

# Object and dependency files in arch-specific build directory
OBJS := $(addprefix $(BUILD_DIR)/, $(SRC_FILES:.c=.o))
DEPS := $(OBJS:.o=.d)

ifeq ($(OS),darwin)
	LDFLAGS = -dynamiclib
	TARGET_LIB := lib/build/libsysres-$(OS)-$(ARCH).dylib
else
	# Bundle RPATH in Linux builds to avoid need for patchelf
	# $ORIGIN allows libraries to be found relative to the library location
	# Additional paths for common library locations
	LDFLAGS += -Wl,-rpath,'$$ORIGIN:/lib/x86_64-linux-gnu:/lib/aarch64-linux-gnu:/lib64:/lib'
	TARGET_LIB := lib/build/libsysres-$(OS)-$(ARCH).so
endif

.PHONY: all
all: $(TARGET_LIB)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Link object files into shared library
$(TARGET_LIB): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

# Compile source files to object files in build directory
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

# Include dependency files if they exist
-include $(DEPS)

# Static linking target (requires musl libc for true static linking on glibc systems)
# Note: True static linking on glibc systems is difficult; consider using musl libc
# Usage: make static
# This attempts to statically link system libraries (libc, libm, libpthread)
STATIC_TARGET_LIB := lib/build/libsysres-$(OS)-$(ARCH)-static.so
ifeq ($(OS),darwin)
	STATIC_TARGET_LIB := lib/build/libsysres-$(OS)-$(ARCH)-static.dylib
endif

.PHONY: static
static: $(OBJS)
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
	-$(RM) -r $(BUILD_DIR)

.PHONY: fclean
fclean: clean
	-$(RM) $(TARGET_LIB) lib/build/libsysres-*-static.*
