---
inclusion: always
---

# Technology Decisions

## Recommended base: RustDesk (chosen)
After comparing the leading open-source options (findings below), the build-on
base is **RustDesk** (https://github.com/rustdesk/rustdesk).

Why RustDesk fits an UltraViewer clone best:
- It is the closest OSS equivalent to the TeamViewer/UltraViewer UX: ID + password
  connect, full remote control, file transfer, chat, clipboard, unattended access
  with a permanent password — most of our target features already exist.
- Self-hostable rendezvous + relay server (`hbbs` + `hbbr`) so we own the infra.
- Native Windows client with low-latency capture/encode (uses hardware codecs).
- Written in Rust (core) with a Flutter UI, actively maintained.

### License reality check — READ THIS
- RustDesk client and **Server OSS** are **AGPL-3.0**.
- AGPL means: if we distribute a modified client, or offer it as a network service,
  we must release our corresponding source under AGPL too. This is fine for an
  open/internal project but is a real constraint for a closed-source commercial
  product. Decide the product's licensing model early.
- "RustDesk Server Pro" is a separate **paid, closed** server — not our base.
- Action item: confirm with the project owner whether the end product will be
  open-source (AGPL OK) or closed-source commercial (then we must either comply
  with AGPL, negotiate a license, or pick a differently-licensed base).

## Options considered
| Project | Language | Model | License | Verdict |
|---|---|---|---|---|
| **RustDesk** | Rust + Flutter | ID/password, P2P + relay, desktop app | AGPL-3.0 | **Chosen** — closest UX to UltraViewer |
| MeshCentral | Node.js + JS | Web console + agents, fleet mgmt | Apache-2.0 | Great license, but web/fleet model, not the "enter ID+password" app UX |
| Apache Guacamole | Java + C | Clientless browser gateway (RDP/VNC/SSH) | Apache-2.0 | Gateway to existing protocols, not a peer app |
| TigerVNC / TightVNC | C/C++ | VNC protocol | GPL | Low-level; no relay/NAT traversal, no account model |
| xrdp | C | RDP server for Linux | Apache-2.0 | Linux-target, wrong platform focus |

If closed-source commercial licensing becomes a hard requirement and AGPL is a
blocker, the fallback is **MeshCentral (Apache-2.0)** reskinned, or a ground-up
build using the component stack below.

## Language guidance (if/when we write our own components)
- **Core engine (capture, encode, input injection, networking): Rust or C++.**
  Rust preferred for memory safety + matches RustDesk; C++ if integrating Win32
  capture APIs directly.
- Windows capture: **Desktop Duplication API (DXGI)** for the screen; **Windows
  Graphics Capture** for per-window; GDI `BitBlt` as a legacy fallback.
- Video codec: **H.264/H.265 via hardware encoders** (NVENC / Intel QSV / AMD VCE),
  software **VP8/VP9 (libvpx)** or AV1 as fallback. RustDesk already does this.
- Input injection: Win32 **SendInput** / `SetCursorPos`; raw input for capture.
- Transport: UDP + reliability layer or QUIC for media; TLS/TCP for control.
  RustDesk uses a custom protocol over its relay with end-to-end NaCl crypto.
- UI: **Flutter** (RustDesk's current UI) or native (WinUI 3 / WPF) if we re-skin.
- Server: Rust (`hbbs` rendezvous, `hbbr` relay).

## Toolchain to install (Windows dev box)
- **Rust** (rustup, stable MSVC toolchain): https://rustup.rs
- **Visual Studio Build Tools** (MSVC v143 + Windows 10/11 SDK) — needed by Rust MSVC.
- **Flutter SDK** (for the client UI) + Dart.
- **vcpkg** (C/C++ deps that RustDesk pulls: libvpx, libyuv, opus, aom, etc.).
- **LLVM/Clang** (bindgen needs libclang).
- **CMake**, **Ninja**, **git**, **Python 3** (build scripts).
- **Docker Desktop** (easiest way to run the self-hosted server for testing).
- Optional: **NASM** (assembly deps for some codecs).

## Verified toolchain (dev machine, 2026-10-28)
| Tool | Version | Location / note |
|---|---|---|
| Rust | 1.99.1 | `stable-x86_64-pc-windows-msvc` (correct target) |
| Flutter / Dart | 3.47.8 / 3.13.7 | on PATH |
| MSVC (cl) | 19.51 | VS 18 (2026) Community, via DevShell |
| Ninja | bundled | ships with VS Build Tools |
| CMake | 4.5.0 | on PATH |
| LLVM/Clang | 23.1.4 | `C:\Program Files\LLVM\bin` (libclang here) |
| vcpkg | 2026-09-26 | `C:\Users\JAYARAJ\vcpkg\vcpkg` (bootstrapped) |
| NASM | 2.16.03 | project-local `tools\nasm-2.16.03` |
| Docker | 28.4.0 | server stack |

- **Sciter is NOT required** — RustDesk's current UI is Flutter (we build that).
  The Sciter instructions on rustdesk.com are the legacy path; skip them.
- Build env is assembled by `scripts/env.ps1` (dot-source it); it does not modify
  the system PATH permanently.

## Server container + Kubernetes (M1)
- Image: `server/Dockerfile` (multi-stage; context = `vendor/rustdesk-server`), build with
  `scripts/build-server-image.ps1`. Debian bookworm-slim runtime, uid 10001, state in `/data`.
- Build-time privacy patch removes hbbs's daily api.rustdesk.com phone-home
  (`--build-arg DISABLE_UPDATE_CHECK=1`, default on).
- Deployment is the Helm chart `helm/jkr-server` (replaced the old kustomize `k8s/`): hostNetwork
  (no LB on the cluster), Recreate, one pod with hbbs+hbbr, prod PVC on Retain class
  `ebs-gp3-database`, `-k _`. prod ports 21115-21119, int 22115-22119. Validate offline:
  `scripts\helm-verify.ps1`. Details: `helm/jkr-server/README.md`.
- CI/CD: GitHub Actions in `.github/workflows/` (ci, deploy-int, deploy-prod), ECR repo `jkr-server`,
  pinned upstream rustdesk-server SHA. See `.github/workflows/README.md`.
- Prod cluster: single kubeadm node (AWS, containerd, Cilium, EBS CSI), SHARED with other prod
  workloads -> never apply without explicit user approval.
- Verified with Docker Desktop on amd64; target node is amd64.

## Build & run — quick reference
Server (self-hosted, Docker — fastest path):
```
docker run --name hbbs -p 21115:21115 -p 21116:21116 -p 21116:21116/udp \
  -p 21118:21118 -v ./data:/root rustdesk/rustdesk-server hbbs
docker run --name hbbr -p 21117:21117 -p 21119:21119 \
  -v ./data:/root rustdesk/rustdesk-server hbbr
```
Client (build from source) — high level:
```
rustup toolchain install stable
# install vcpkg deps (libvpx, libyuv, opus, aom) per RustDesk docs
python3 build.py        # RustDesk's helper, or: cargo build --release
```
These are starting points; exact steps get pinned down and recorded in
`progress-log.md` once we run them.
