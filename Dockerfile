# syntax=docker/dockerfile:1.7
FROM python:3.11-slim AS base
SHELL ["/bin/bash", "-c"]

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl build-essential git ssh sudo wget zip unzip \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir pipx && pipx ensurepath

ENV NVM_VERSION=0.40.3 \
    NODE_VERSION=22.18.0 \
    NVM_DIR=/root/.nvm
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash \
 && . "$NVM_DIR/nvm.sh" \
 && nvm install ${NODE_VERSION} \
 && nvm alias default v${NODE_VERSION}
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}:/root/.local/bin"

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo
ENV PATH="${CARGO_HOME}/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --profile minimal \
 && rustup component add rust-analyzer

WORKDIR /workspaces/serena

# Copy everything first (loses some layer-cache efficiency but is bulletproof)
COPY . /workspaces/serena/

# Single sync: installs deps from lockfile AND the project itself (with scripts)
RUN uv venv \
 && VIRTUAL_ENV=/workspaces/serena/.venv uv sync --frozen --no-dev
ENV PATH="/workspaces/serena/.venv/bin:${PATH}" \
    VIRTUAL_ENV="/workspaces/serena/.venv"

ENV SERENA_HOME=/workspaces/serena/config
RUN mkdir -p "$SERENA_HOME" \
 && cp src/serena/resources/serena_config.template.yml "$SERENA_HOME/serena_config.yml" \
 && sed -i \
        -e 's/^gui_log_window: .*/gui_log_window: False/' \
        -e 's/^web_dashboard_listen_address: .*/web_dashboard_listen_address: 0.0.0.0/' \
        -e 's/^web_dashboard_open_on_launch: .*/web_dashboard_open_on_launch: False/' \
        "$SERENA_HOME/serena_config.yml"

EXPOSE 9121 24282

ENTRYPOINT ["/bin/bash", "-c", "source .venv/bin/activate && exec \"$0\" \"$@\""]

# ---- production stage required by compose.yaml ----
FROM base AS production
CMD ["uv", "run", "--directory", ".", "serena-mcp-server", \
     "--transport", "sse", "--port", "9121", "--host", "0.0.0.0"]
