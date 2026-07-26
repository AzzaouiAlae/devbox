# C / C++ dev container - written by `devbox init cpp`. Your project's file now.
# Image pinned to a concrete tag (not :latest); it ships gcc, g++, gdb, make,
# cmake and vcpkg.
FROM mcr.microsoft.com/devcontainers/cpp:3.0.1-bookworm

USER root

# The docker CLIENT only - no second daemon in here. It talks to your own daemon
# on the machine through the socket this dev container mounts. Pinned to the same
# versions devbox installs for your shell, so compose behaves the same in both.
ARG DOCKER_CLI_VERSION=29.6.2
ARG COMPOSE_VERSION=v5.3.1
ARG BUILDX_VERSION=v0.35.0
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) darch=x86_64;  garch=amd64 ;; \
      arm64) darch=aarch64; garch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${darch}/docker-${DOCKER_CLI_VERSION}.tgz" \
      | tar -xz -C /tmp docker/docker; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${darch}"; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-buildx \
      "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${garch}"; \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose \
             /usr/local/lib/docker/cli-plugins/docker-buildx; \
    docker --version; docker compose version; docker buildx version

RUN g++ --version && cmake --version
