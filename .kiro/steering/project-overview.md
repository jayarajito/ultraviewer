---
inclusion: always
---

# Project: JustKeepRemote — UltraViewer-style Windows Remote Desktop

## Product name
**JustKeepRemote** (working name, may change later).

## Goal
Build a complete remote desktop support application for Windows, functionally
equivalent to UltraViewer (https://www.ultraviewer.net). A helper must be able
to view and fully control a partner's Windows PC as if sitting in front of it.

## Licensing (decided)
- The project is **open-source**.
- Base: **RustDesk (AGPL-3.0)**. AGPL is acceptable because our product is itself
  open-source. If we distribute modified clients or run it as a network service,
  we publish our corresponding source under AGPL-3.0. See `tech-stack.md`.

## Infrastructure (decided)
- **Dev:** self-hosted server via local Docker (hbbs + hbbr).
- **Production:** our self-hosted single-node Kubernetes cluster.

## Core feature set (target parity with UltraViewer)
- Connect model: each PC shows an **ID + password**; helper enters them to connect.
- Full remote control: real-time screen streaming + remote mouse & keyboard.
- Multi-monitor support and monitor switching.
- File transfer (send/receive, pause/resume/cancel), available during a session.
- In-session text chat (toggleable, hotkey).
- Unattended access: fixed/private custom password + "start with Windows".
- Multi-session support (control several PCs, be controlled by several helpers).
- Clipboard sync between local and remote.
- Session security: encrypted transport, per-session password, connect approval.
- No time limits / no nag popups (UltraViewer's selling point).

## Non-goals (for now)
- macOS / Linux / mobile clients (Windows-first; architecture should not block them later).
- Enterprise SSO/LDAP, billing, device fleet management.

## Guiding principles
- Build on a proven open-source base rather than from zero. See `tech-stack.md`.
- Self-hosted rendezvous/relay server; we own the infrastructure.
- Security first: end-to-end encryption, explicit consent, least privilege.
- Ship module by module, each independently testable.

## How we work
- `tech-stack.md` holds the technology decisions and the chosen OSS base.
- `architecture.md` holds the system design and module breakdown.
- `progress-log.md` is the living record of DONE / IN PROGRESS / NEXT.
  **Always update `progress-log.md` at the end of a work session.**
