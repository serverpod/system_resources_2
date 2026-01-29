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

# =============================================================================
# Docker-based builds for cross-platform Linux binaries
# These targets use the same Dockerfile.build used by CI for reproducibility
# Note: i686 uses native cross-compilation (gcc -m32) since gcc image doesn't support linux/386
# =============================================================================

DOCKER_PLATFORMS := linux/amd64 linux/arm64 linux/arm/v7

.PHONY: docker-build
docker-build:
	@echo "Building native library for current platform using Docker..."
	docker build -f ci/Dockerfile.build --output type=local,dest=lib/build .

.PHONY: docker-build-all
docker-build-all:
	@echo "Building native libraries for all Linux platforms..."
	@for platform in $(DOCKER_PLATFORMS); do \
		echo "Building for $$platform..."; \
		docker build --platform $$platform -f ci/Dockerfile.build --output type=local,dest=lib/build . || exit 1; \
	done
	@echo "Building for i686 (cross-compilation, cached)..."
	docker build --platform linux/amd64 -f ci/Dockerfile.build-i686 --output type=local,dest=lib/build .
	@echo "All Linux binaries built successfully!"
	@ls -la lib/build/libsysres-linux-*.so

.PHONY: docker-build-amd64
docker-build-amd64:
	docker build --platform linux/amd64 -f ci/Dockerfile.build --output type=local,dest=lib/build .

.PHONY: docker-build-arm64
docker-build-arm64:
	docker build --platform linux/arm64 -f ci/Dockerfile.build --output type=local,dest=lib/build .

.PHONY: docker-build-armv7
docker-build-armv7:
	docker build --platform linux/arm/v7 -f ci/Dockerfile.build --output type=local,dest=lib/build .

# i686 uses cross-compilation since gcc Docker image doesn't support linux/386
# Uses a dedicated Dockerfile with cached gcc-multilib layer
.PHONY: docker-build-i686
docker-build-i686:
	@echo "Building i686 using cross-compilation (cached)..."
	docker build --platform linux/amd64 -f ci/Dockerfile.build-i686 --output type=local,dest=lib/build .

# =============================================================================
# Convenience targets for building all binaries
# =============================================================================

# Build all Linux binaries (requires Docker)
# Outputs: libsysres-linux-{x86_64,aarch64,armv7l,i686}.so
.PHONY: build-all-linux
build-all-linux: docker-build-all
	@echo "All Linux binaries are ready in lib/build/"

# Build all macOS binaries (requires running on macOS with Xcode)
# Outputs: libsysres-darwin-{arm64,x86_64}.dylib
.PHONY: build-all-macos
build-all-macos:
	@if [ "$$(uname)" != "Darwin" ]; then \
		echo "Error: macOS builds require running on macOS"; \
		exit 1; \
	fi
	@echo "Building macOS x86_64..."
	@$(MAKE) clean
	@arch -x86_64 $(MAKE)
	@echo "Building macOS ARM64..."
	@$(MAKE) clean
	@arch -arm64 $(MAKE)
	@echo "All macOS binaries built successfully!"
	@ls -la lib/build/libsysres-darwin-*.dylib

# Build everything (Linux via Docker, macOS if on macOS)
.PHONY: build-all
build-all: build-all-linux
	@if [ "$$(uname)" = "Darwin" ]; then \
		echo "Detected macOS, also building macOS binaries..."; \
		$(MAKE) build-all-macos; \
	fi
	@echo "All binaries built!"
	@ls -la lib/build/libsysres-*
