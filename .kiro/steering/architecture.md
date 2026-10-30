---
inclusion: always
---

# Architecture

## High-level picture
```
          ┌─────────────────────────────────────────────┐
          │         Self-hosted Server (we run)          │
          │                                              │
          │   hbbs (Rendezvous/ID)     hbbr (Relay)      │
          │   - registers peer IDs     - forwards media  │
          │   - brokers P2P hole-punch   when P2P fails  │
          └───────▲───────────────────────────▲──────────┘
                  │ register / lookup          │ relayed stream (fallback)
                  │                            │
        ┌─────────┴─────────┐        ┌─────────┴─────────┐
        │  Controller app   │        │   Partner app     │
        │  (the helper)     │◀──────▶│  (controlled PC)  │
        │  enters ID+pass   │  P2P   │  shows ID+pass    │
        └───────────────────┘ direct └───────────────────┘
                              (preferred)
```
- Each PC runs the **same app**; it can act as controller, partner, or both.
- Connection: register with `hbbs` → exchange → try **direct P2P** (NAT hole
  punch) → fall back to **relay (`hbbr`)** if P2P fails.
- Media and input are **end-to-end encrypted**; the server never sees plaintext.

## Client module breakdown
1. **Connection/Session** — ID registration, password auth, consent prompt,
   P2P negotiation, relay fallback, session lifecycle, encryption handshake.
2. **Screen capture** — DXGI Desktop Duplication (full screen / per monitor),
   Windows Graphics Capture (per window), dirty-region tracking, cursor capture.
3. **Encode/Decode** — HW H.264/H.265 (NVENC/QSV/VCE) with VP8/VP9/AV1 software
   fallback; adaptive bitrate based on measured bandwidth/latency.
4. **Input injection** — remote mouse/keyboard via SendInput; coordinate mapping
   across multi-monitor; special keys (Ctrl+Alt+Del via a privileged helper).
5. **File transfer** — browse remote FS, send/receive, pause/resume/cancel,
   progress, integrity check.
6. **Chat** — in-session text messaging, toggle hotkey.
7. **Clipboard sync** — text (and later files/images) both directions.
8. **Unattended access** — permanent password store (hashed), run-at-startup
   service, auto-launch on boot before login (Windows service + session hook).
9. **UI** — connect screen (your ID/password + remote ID/password entry),
   session toolbar (monitors, file transfer, chat, quality, end session).
10. **Security** — key management, per-session passwords, access control,
    audit log, consent/approval before control starts.

## Server module breakdown
- **hbbs (rendezvous)** — ID registry, peer discovery, NAT traversal brokering.
- **hbbr (relay)** — encrypted stream relay when direct P2P isn't possible.
- **Key management** — server keypair for client config; clients pin it.
- (Later) **account/admin** — address book, device list, logs.

## Windows-specific hard problems (plan for these early)
- **UAC / secure desktop**: controlling elevated prompts and the Ctrl+Alt+Del
  / login screen needs a **Windows service running as SYSTEM** that injects into
  the active session (session 0 isolation). RustDesk ships this — study it.
- **Capture before login / on lock screen**: requires the SYSTEM service.
- **Multi-monitor + DPI scaling**: normalize coordinates; handle per-monitor DPI.
- **Antivirus/SmartScreen**: a remote-control app gets flagged; plan code signing.

## Delivery roadmap (module by module)
- **M0 Foundations** — toolchain installed, clone RustDesk, build client + server,
  get a local connection working end to end. *(proves the base before we modify)*
- **M1 Server** — self-host hbbs/hbbr; pin our own key; clients use our server.
- **M2 Core session** — reliable connect by ID+password, screen view + control.
- **M3 Quality** — multi-monitor, adaptive bitrate, clipboard.
- **M4 File transfer** — full send/receive with resume.
- **M5 Chat**.
- **M6 Unattended access** — permanent password + run-at-startup service.
- **M7 Security pass** — crypto review, consent flows, audit log.
- **M8 Branding/packaging** — rename, icons, installer (MSI/Inno Setup), signing.

Each milestone ends with a working, testable build and a `progress-log.md` update.
