# JustKeepRemote

An open-source, UltraViewer-style remote desktop for Windows. A helper enters a partner's ID and
password to see and control their PC. No time limits, no nag screens, and it talks only to a server
you run yourself.

JustKeepRemote is a modified build of [RustDesk](https://github.com/rustdesk/rustdesk) 1.5.1 and the
[rustdesk-server](https://github.com/rustdesk/rustdesk-server) 1.1.17 (hbbs + hbbr). It is licensed
under the **GNU AGPL v3** (see `LICENSE`). Upstream copyright notices are kept.

## What is different from upstream RustDesk

- Preconfigured for our server (`jkr.jayarajnarayanan.in`) and its public key. No setup script needed.
- The server address, relay and key are locked in the UI.
- Renamed and re-branded (own settings folder `%APPDATA%\JustKeepRemote`, own Windows service name).
- The client never contacts rustdesk.com (update check, hardware-fingerprint upload, default API host and
  the public fallback server are removed). The server image removes the same upstream phone-home.
- Everything is built from source by GitHub Actions from a pinned upstream commit.

All client changes live in `client/apply-jkr-patches.ps1`, applied to the pinned upstream checkout.
That script is the corresponding source for our changes.

## Using the client

1. Download the zip from the latest [release](../../releases) and check it against the `.sha256` file.
2. Unzip and run `JustKeepRemote.exe`. The bottom-left should show **Ready**.
3. Give the helper your **ID** and password, or enter a partner's ID to connect.
4. For unattended access, UAC prompts and the Windows login screen, click **Install** (accept the UAC
   prompt) and set a permanent password in Settings > Security. Installing registers a Windows service.

**Updates.** About every 12 hours the app asks GitHub (`api.github.com`, anonymous, no identifiers sent
besides your IP) whether a newer release of this project exists. If so, the home screen shows a banner whose
button opens the release page. Nothing is downloaded or installed automatically. Turn it off under
Settings > General ("check for software update"). This needs the repository to be public.

**Minimize.** On an installed copy, the minimize button hides the window completely and the tray icon brings
it back (Settings > General > "Hide window when minimized" turns this off). The tray icon always stays, and
an incoming connection still shows its normal window, so the app is never invisible to the person using the PC.

The build is not code-signed, so Windows SmartScreen may say "unknown publisher". Some antivirus
products flag any remote-control software.

## Repository layout

| Path | What it is |
|---|---|
| `client/` | Patch script for the RustDesk client, plus placeholder icons (`client/branding`) |
| `server/` | `Dockerfile` (server image built from source) and local dev compose |
| `helm/jkr-server/` | Helm chart for the server (see its README) |
| `.github/workflows/` | CI, server deploy (int, prod) and the Windows client build (see its README) |
| `scripts/` | Local build, packaging and verification helpers |
| `.kiro/steering/` | Project notes: decisions, build recipe, progress log |

## Server

The server is two processes in one pod: `hbbs` (ID/rendezvous) and `hbbr` (relay).

| | prod | int |
|---|---|---|
| TCP | 21115-21119 | 22115-22119 |
| UDP | 21116 | 22116 |

Open those ports to clients on the node's firewall / security group. Clients use the standard prod ports
without any `:port` suffix. The server's keypair is created on first start in `/data`; **back up the
private key** (`id_ed25519`) once and never commit it, or every client is rejected if the volume is lost.
Details: `helm/jkr-server/README.md` and `.github/workflows/README.md`.

Local server for development:

```
powershell -File scripts\build-server-image.ps1
powershell -File scripts\dev-server-up.ps1
```

## Building

- **Server image + deploy:** push to `development` deploys int; prod is a manual workflow run from `main`.
- **Windows client:** Actions > "Build client (Windows)" (manual). Tick `release` and give a tag to get a
  draft release. A cold build takes about an hour.
- **Locally on Windows:** needs Rust, Visual Studio Build Tools, LLVM, vcpkg, NASM and Flutter 3.24.5. The
  exact recipe is in `.kiro/steering/progress-log.md` and `.kiro/steering/tech-stack.md`; the entry point is
  `scripts/shortpath-build.ps1`, then `scripts/package-client.ps1`.

## Source and licence

The corresponding source of any released binary is this repository at the release tag, applied to the
upstream commits named in the release notes. RustDesk is Copyright Purslane Tech Pte. Ltd. and contributors.
This project is not affiliated with or endorsed by RustDesk.
