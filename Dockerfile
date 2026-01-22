# Dockerfile for testing system_resources with native assets
# Uses Dart 3.10 (native assets is stable in Dart 3.5+)

FROM dart:3.10

# Install C compiler for native assets (clang is required by native_toolchain_c)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files first for better caching
COPY pubspec.yaml .
COPY analysis_options.yaml .

# Get dependencies
RUN dart pub get

# Copy the rest of the source code
COPY . .

# Verify code analyzes correctly
RUN dart analyze

# Run tests
RUN dart test

# Run example to verify it works
CMD ["dart", "run", "example/example.dart"]
