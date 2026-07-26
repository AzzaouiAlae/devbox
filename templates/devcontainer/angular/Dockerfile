# Angular dev container — written by `devbox init angular`. It is your project's
# file now: edit it, commit it, review it like code.
#
# Node is pinned to one exact version on purpose. That same version must appear in
#   src/Angular/.nvmrc
#   the "engines" field of src/Angular/package.json
#   the build stage of the application's own Dockerfile
#   this line
# If they drift you write code on one Node and the build uses another, and nothing
# in the source looks wrong. `devbox check-versions` fails when they disagree.
ARG NODE_VERSION=24.18.0
FROM node:${NODE_VERSION}-bookworm

USER root

# The docker CLIENT only — there is no second daemon in here. It talks to your own
# daemon on the machine through the socket this dev container mounts. Pinned to
# the same versions devbox installs for your shell, so `docker compose` behaves
# identically inside and outside the container.
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

# The Angular command line tool, pinned. Once a project lists its own copy in
# package.json, that copy is what runs inside the project — this one is for
# creating a workspace and for commands outside one.
ARG ANGULAR_CLI_VERSION=22.0.8
RUN npm install -g "@angular/cli@${ANGULAR_CLI_VERSION}" \
 && npm cache clean --force \
 && ng version || true
