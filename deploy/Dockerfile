FROM --platform=linux/amd64 dart:stable AS build

WORKDIR /app
COPY main.dart monitor.c ./

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/* && \
    gcc -shared -fPIC -O2 -o libmonitor.so monitor.c

RUN dart compile exe main.dart -o monitor

FROM debian:bookworm-slim
WORKDIR /app

COPY --from=build /app/monitor /app/monitor
COPY --from=build /app/libmonitor.so /app/libmonitor.so

USER 1000

CMD ["./monitor"]
