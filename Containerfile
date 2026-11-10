# VHSFin – Flutter-Web-Build + Python-Helper (incl. /ia- and /vc-Proxy)
# Build:  podman build --format docker -t localhost/vhsfin:latest -f Containerfile .
#         (--format docker, otherwise podman ignores the HEALTHCHECK)
# Optional: --build-arg VHSFIN_REF=<tag|commit> --build-arg VHSCOLLECTOR=true --build-arg DEMO=true
#           --build-arg FLUTTER_VERSION=… --build-arg FLUTTER_SHA256=… (values from releases_linux.json)

############################
# Stage 1: Flutter-Build
############################
FROM docker.io/library/debian:trixie-slim AS build

# VHSFin requires Dart >= 3.13.2  ->  Flutter >= 3.47.2
ARG FLUTTER_VERSION=3.47.9
ARG FLUTTER_SHA256=25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a
ARG VHSFIN_REPO=https://github.com/markdid/vhsfin.git
ARG VHSFIN_REF=main
ARG VHSCOLLECTOR=false
ARG DEMO=false
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 builder

# Flutter-SDK from the official release archive
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && chown -R builder:builder /opt/flutter

USER builder
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
WORKDIR /home/builder/src

RUN git clone --depth 1 --branch "${VHSFIN_REF}" "${VHSFIN_REPO}" . \
 || (git clone "${VHSFIN_REPO}" . && git checkout "${VHSFIN_REF}")

RUN flutter --disable-analytics \
 && flutter config --no-analytics --enable-web \
 && flutter --version \
 && flutter build web --release \
      --dart-define=VHSFIN_VHSCOLLECTOR=${VHSCOLLECTOR} \
      --dart-define=VHSFIN_DEMO=${DEMO}

############################
# Stage 2: Runtime (slim)
############################
FROM docker.io/library/python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    VHSFIN_PORT=8080

RUN useradd --uid 10001 --no-create-home --home-dir /app --shell /usr/sbin/nologin vhsfin
WORKDIR /app

COPY --from=build --chown=10001:10001 /home/builder/src/tool/serve_web.py /app/tool/serve_web.py
COPY --from=build --chown=10001:10001 /home/builder/src/build/web /app/build/web

USER 10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"VHSFIN_PORT\",\"8080\")}/ia/health', timeout=4)" || exit 1

CMD ["sh", "-c", "exec python3 /app/tool/serve_web.py --port \"${VHSFIN_PORT}\" --root /app/build/web"]
