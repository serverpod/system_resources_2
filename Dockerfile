# Dockerfile for testing system_resources with container-aware features
#
# Container-aware testing:
# Build:  docker build -t system_resources_test .
# Run with limits: docker run --memory=256m --cpus=0.5 system_resources_test
#
# Expected output when running with limits:
# - Container environment: true
# - Memory limit: ~256 MB
# - CPU limit: ~0.5 cores

FROM dart:stable

# Install build tools for compiling native library
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files first for better caching
COPY pubspec.yaml .

# Get dependencies
RUN dart pub get

# Copy the rest of the source code
COPY . .

# Build native library with new container-aware functions
RUN make

# Verify code analyzes correctly
RUN dart analyze

# Run tests
RUN dart test

# Run example to verify it works (shows container-aware resource info)
CMD ["dart", "run", "example/example.dart"]
