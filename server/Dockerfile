# syntax=docker/dockerfile:1.7
#
# JustKeepRemote server image — built FROM SOURCE (vendor/rustdesk-server).
# Contains hbbs (ID/rendezvous), hbbr (relay) and rustdesk-utils.
#
# Build context MUST be vendor/rustdesk-server (see scripts/build-server-image.ps1):
#   docker build -f server/Dockerfile -t jkr-server:dev vendor/rustdesk-server
#
# One image, two commands: run `hbbs ...` and `hbbr ...` as separate containers.

############################
# Stage 1: build
############################
FROM rust:1-bookworm AS build

# clang/libclang: some build-deps use bindgen. libsodium is built from the
# bundled source (static) by libsodium-sys, which only needs a C toolchain + make.
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang libclang-dev pkg-config make \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

# PRIVACY PATCH (default ON): upstream hbbs calls check_software_update() at
# startup, which POSTs OS name/version, CPU arch and a persistent hardware device
# fingerprint to https://api.rustdesk.com/version/latest every 24h, with no opt-out
# flag. We own this server, so remove the call. Applied to the COPY in this image
# only (vendor/ stays pristine). The build FAILS if the patch did not apply.
ARG DISABLE_UPDATE_CHECK=1
RUN if [ "$DISABLE_UPDATE_CHECK" = "1" ]; then \
      sed -i '/crate::common::check_software_update();/d' src/main.rs \
      && ! grep -q 'check_software_update();' src/main.rs \
      && echo "patched: update check removed from hbbs"; \
    fi

# --locked: honour Cargo.lock exactly (reproducible). Cache mounts keep the cargo
# registry/git checkouts and target dir between builds (big win on slow networks).
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    cargo build --release --locked \
 && mkdir -p /out \
 && cp target/release/hbbs target/release/hbbr target/release/rustdesk-utils /out/

############################
# Stage 2: runtime
############################
FROM debian:bookworm-slim AS runtime

# ca-certificates: rustls-tls-native-roots reads the system trust store.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 jkr \
 && useradd  --system --uid 10001 --gid 10001 --home-dir /data --shell /usr/sbin/nologin jkr \
 && mkdir -p /data && chown 10001:10001 /data

COPY --from=build /out/hbbs /out/hbbr /out/rustdesk-utils /usr/local/bin/

# The servers keep EVERYTHING under the working dir / HOME: the keypair
# (id_ed25519[.pub]), the peer DB (db_v2.sqlite3) and a .config dir.
# Mount one persistent volume at /data.
ENV HOME=/data
WORKDIR /data
VOLUME /data
USER 10001:10001

# hbbs: 21115/tcp (NAT test) 21116/tcp+udp (registration/signalling) 21118/tcp (ws)
# hbbr: 21117/tcp (relay)                                           21119/tcp (ws)
EXPOSE 21115 21116/tcp 21116/udp 21117 21118 21119

CMD ["hbbs"]
