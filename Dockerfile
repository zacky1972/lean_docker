# syntax=docker/dockerfile:1

ARG DEBIAN_VERSION=bookworm-slim

FROM debian:${DEBIAN_VERSION} AS elan-downloader

ARG TARGETARCH
ARG ELAN_VERSION=4.2.4

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && case "${TARGETARCH}" in \
         amd64) \
           elan_arch="x86_64-unknown-linux-gnu"; \
           elan_sha256="42b94d4244e8353142c456ec0e4ca6528fd898a6c604d4059f494e706e431f63" \
           ;; \
         arm64) \
           elan_arch="aarch64-unknown-linux-gnu"; \
           elan_sha256="05febd124d84ebf994b2e7479922a5650b1e950c17ae3bd1ddd776b65bb72bf9" \
           ;; \
         *) \
           echo "Unsupported architecture: ${TARGETARCH}" >&2; \
           exit 1 \
           ;; \
       esac \
    && curl --fail --location --silent --show-error \
         --output /tmp/elan.tar.gz \
         "https://github.com/leanprover/elan/releases/download/v${ELAN_VERSION}/elan-${elan_arch}.tar.gz" \
    && echo "${elan_sha256}  /tmp/elan.tar.gz" | sha256sum --check --strict \
    && mkdir /out \
    && tar --extract --gzip --file /tmp/elan.tar.gz --directory /out

FROM debian:${DEBIAN_VERSION}

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --shell /bin/bash lean \
    && mkdir /workspace \
    && chown lean:lean /workspace

ENV ELAN_HOME=/home/lean/.elan
ENV PATH=/home/lean/.elan/bin:${PATH}

COPY --from=elan-downloader /out/elan-init /usr/local/bin/elan-init

RUN elan-init --yes --no-modify-path --default-toolchain none \
    && rm /usr/local/bin/elan-init \
    && chown --recursive lean:lean /home/lean/.elan

USER lean
WORKDIR /workspace

# The project, rather than the image, is the source of truth for the Lean version.
COPY --chown=lean:lean lean-toolchain ./lean-toolchain

RUN toolchain="$(tr -d '\r\n' < lean-toolchain)" \
    && test -n "${toolchain}" \
    && elan toolchain install "${toolchain}" \
    && elan default "${toolchain}" \
    && lean --version \
    && lake --version

COPY --chown=lean:lean . .

CMD ["bash"]
