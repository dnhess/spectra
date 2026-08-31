FROM --platform=linux/amd64 node:20-bookworm-slim@sha256:3d0f05455dea2c82e2f76e7e2543964c30f6b7d673fc1a83286736d44fe4c41c AS codex-package
ARG CODEX_VERSION
WORKDIR /opt/codex-package
RUN test -n "${CODEX_VERSION}" \
    && npm init --yes >/dev/null \
    && npm install --ignore-scripts --no-audit --no-fund "@openai/codex@${CODEX_VERSION}" \
    && test -x node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex \
    && install -D -m 0555 \
      node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex \
      /opt/codex/codex

FROM --platform=linux/amd64 python:3.12-slim-bookworm@sha256:4427763a1ba36f5aa8f656a03e5d00f3b8d61f5dd950c73df6c14f8c7640f8ab
ARG CODEX_BINARY_SHA256
COPY --from=codex-package /opt/codex/codex /usr/local/bin/codex
COPY codex-executor.py /opt/spectra/codex-executor.py
RUN test "${#CODEX_BINARY_SHA256}" -eq 64 \
    && printf '%s' "${CODEX_BINARY_SHA256}" | grep -Eq '^[0-9a-f]{64}$' \
    && printf '%s  %s\n' "${CODEX_BINARY_SHA256}" /usr/local/bin/codex | sha256sum --check --strict \
    && python3 -c "import pathlib, struct; data = pathlib.Path('/usr/local/bin/codex').read_bytes()[:20]; assert data[:4] == b'\\x7fELF' and data[4] == 2 and data[5] == 1 and struct.unpack('<H', data[18:20])[0] == 62" \
    && groupadd --gid 65532 spectra \
    && useradd --uid 65532 --gid 65532 --home-dir /home/spectra --create-home --shell /usr/sbin/nologin spectra \
    && chmod 0555 /usr/local/bin/codex /opt/spectra/codex-executor.py
USER 65532:65532
