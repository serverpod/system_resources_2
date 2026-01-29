# Dockerfile for testing system_resources with pre-compiled binaries
# No C compiler needed - uses pre-compiled .so files

FROM dart:stable

WORKDIR /app

# Copy package files first for better caching
COPY pubspec.yaml .

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
