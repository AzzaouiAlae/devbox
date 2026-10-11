# Generic dev container - written by `devbox init base`. Your project's file now.
# Image and every tool pinned to a concrete version (not :latest). Ready for web
# and .NET work: Node + npm, the Angular CLI, TypeScript, the Tailwind CLI and the
# .NET SDK. Remove what your project does not need, add what it does.
FROM mcr.microsoft.com/devcontainers/base:3.0.3-noble

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

# The .NET SDK, in the place Microsoft's own images use.
ARG DOTNET_SDK_VERSION=10.0.401
ENV DOTNET_ROOT=/usr/share/dotnet
RUN set -eux; \
    curl -fsSL -o /tmp/dotnet-install.sh https://dot.net/v1/dotnet-install.sh; \
    bash /tmp/dotnet-install.sh --version "${DOTNET_SDK_VERSION}" --install-dir "$DOTNET_ROOT" --no-path; \
    ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet; \
    rm /tmp/dotnet-install.sh; \
    dotnet --info

# Node and npm from the official tarball, checked against its published checksum.
ARG NODE_VERSION=24.21.0
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) narch=x64 ;; \
      arm64) narch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    f="node-v${NODE_VERSION}-linux-${narch}.tar.xz"; \
    cd /tmp; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${f}"; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${f}\$" | sha256sum -c -; \
    tar -xJf "$f" -C /usr/local --strip-components=1 --no-same-owner; \
    rm "$f"; \
    node --version; npm --version

# The Angular CLI and TypeScript (`ng`, `tsc`). Once a project lists its own copy
# in package.json, that copy is what runs inside the project - these are for
# creating a workspace and for commands outside one.
ARG ANGULAR_CLI_VERSION=22.2.1
ARG TYPESCRIPT_VERSION=7.0.2
ENV NG_CLI_ANALYTICS=false
RUN npm install -g "@angular/cli@${ANGULAR_CLI_VERSION}" "typescript@${TYPESCRIPT_VERSION}" \
 && npm cache clean --force \
 && ng version && tsc --version

# The Tailwind CLI as its standalone binary: Tailwind is built in, so
# `tailwindcss -i in.css -o out.css` works in any folder without node_modules.
ARG TAILWIND_VERSION=4.3.3
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) tarch=x64 ;; \
      arm64) tarch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    f="tailwindcss-linux-${tarch}"; \
    cd /tmp; \
    curl -fsSLO "https://github.com/tailwindlabs/tailwindcss/releases/download/v${TAILWIND_VERSION}/${f}"; \
    curl -fsSL "https://github.com/tailwindlabs/tailwindcss/releases/download/v${TAILWIND_VERSION}/sha256sums.txt" \
      | grep "  \./${f}\$" | sha256sum -c -; \
    install -m 0755 "$f" /usr/local/bin/tailwindcss; \
    rm "$f"; \
    tailwindcss --help | head -1
