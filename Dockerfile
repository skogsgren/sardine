FROM node:22-trixie-slim
ENV DEBIAN_FRONTEND=noninteractive

# python3-.* is here for common packages without requiring venv
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        make \
        file \
        ca-certificates \
        curl \
        git \
        jq \
        less \
        ripgrep \
        unzip \
        wget \
        xz-utils \
        python3 \
        python3-pip \
        python3-venv \
        python3-numpy \
        python3-pandas \
        python3-pydantic \
        python3-pytest \
        python3-matplotlib \
        python3-build \
        python3-wheel \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# python tooling
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
RUN UV_TOOL_DIR=/opt/uv/tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install poetry && uv tool install ruff

# fnm: binary in the image, downloaded Node versions under $FNM_DIR in the volume.
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/bin --skip-shell \
    && fnm --version

RUN mkdir -p /home/node/.local/bin /home/node/.cache \
    && echo 'sandbox home volume' > /home/node/.keep \
    && chown -R node:node /home/node

ENV FNM_DIR=/home/node/.local/share/fnm \
    NPM_CONFIG_PREFIX=/home/node/.local \
    UV_TOOL_BIN_DIR=/home/node/.local/bin \
    PATH=$PATH:/home/node/.local/bin:/home/node/.opencode/bin:/home/node/.cargo/bin

ENV LITELLM_API_KEY=placeholder-not-a-key

RUN printf '%s\n' \
      'eval "$(fnm env --use-on-cd --shell bash)"' \
      'PS1="(sandbox) \w \$ "' \
      >> /etc/bash.bashrc

USER node
