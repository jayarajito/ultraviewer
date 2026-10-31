---
inclusion: always
---

# Progress Log (living memory)

> Update this at the end of every work session. Newest entry on top.
> Legend: âœ… done Â· ðŸš§ in progress Â· â­ï¸ next Â· â“ open question / needs decision

## Current status: âœ… M0 complete Â· âœ… M1 image Â· âœ… CI/CD + Helm written & locally verified (NOT yet run on GitHub/cluster)

### âœ… CI/CD + Helm (2026-10-30/31) â€” modelled on user's `existingapp` (lotto) pipeline
- **Helm chart** `helm/jkr-server` (replaces the old kustomize `k8s/`, now deleted). Release `jkr-server`,
  namespaces `jkr-int` / `jkr-prod`. hostNetwork, Recreate, 1 replica, PVC keep-policy in prod.
  Ports: prod 21115-21119, int 22115-22119 (coexist on one node). `relayHost` required (schema + template).
- **getent guard**: hbbs silently drops an unresolvable `-r` host -> start script exits 1; deploy smoke test
  also greps `relay-servers=["<host>:<port>"]` in the hbbs log.
- **Workflows** (`.github/workflows/`): `ci.yml` (helm-verify, hadolint, SG-script tests, shellcheck,
  actionlint), `deploy-int.yml` (2 jobs: build+smoke+push to ECR, then deploy), `deploy-prod.yml`
  (manual, promotes an existing 12-char SHA tag, `production` Environment, warns about Recreate outage).
  `.github/workflows/README.md` lists secrets/vars/one-time setup. Upstream rustdesk-server pinned to
  full SHA `873230e3...` (`UPSTREAM_REF`), privacy-patch anchor verified at build time.
- **SG allowlist script** `scripts/whitelist-public-ip/whitelist-runner-ip-and-rm.py` (our own; user's
  original wasn't copied). 13 unit tests pass.
- **Verified locally:** `helm-verify` (lint --strict, render int+prod, guard rails, kubeconform 8/8),
  image smoke test (all sections), SG tests, actionlint clean, shellcheck (warning+) clean, hadolint
  (error threshold) clean.
- **NOT verified:** any real GitHub run, ECR push, SG edits, hostNetwork on Cilium, UDP 21116 reachability,
  EBS PVC bind, real clients against the new server.
- **Dropped:** `$schema` line in `values.schema.json` (editor tool refused remote URL; optional in Helm).
- **User TODO before first run:** create ECR repo `jkr-server`; GitHub Environments `int` + `production`
  with secrets `KUBECONFIG_B64`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and vars `ECR_REPOSITORY`,
  `AWS_REGION`, `K8S_SECURITY_GROUP_ID`, `RELAY_HOST`; open node SG (prod TCP 21115-21119 + UDP 21116);
  DNS for RELAY_HOST; then push to development (auto-deploys int, approval issue gates cluster access).
  After first prod install: back up `/data/id_ed25519` (see helm/jkr-server/README.md).
- **User setup DONE (2026-10-31):** git branch renamed to `development` (workflows now trigger on
  `development`, not main); all GitHub secrets/variables created; AWS SG inbound TCP 21115-21119 +
  UDP 21116 from 0.0.0.0/0 added; Elastic IP attached (54.81.13.170); DNS `jkr.jayarajnarayanan.in`
  -> 54.81.13.170, so `RELAY_HOST=jkr.jayarajnarayanan.in`.
- **User's original SG script** is at `existingapp/` (description "GitHub Runner IP", removes ALL old rules with
  that description -> would clash with other apps' deploys). Decision: KEEP our own tagged script.
- **No Ingress / TLS certificate needed** for jkr.jayarajnarayanan.in: RustDesk speaks raw TCP/UDP with its
  own end-to-end NaCl encryption on hostNetwork ports; an HTTP ingress cannot proxy it. Only a DNS A record
  is required. (Certs would matter only for a future web client on the ws ports 21118/21119.)
- **Key backup explained to user:** after first prod install, `kubectl -n jkr-prod exec deploy/jkr-server -c hbbs
  -- cat /data/id_ed25519` -> password manager; never commit. Losing it = all clients rejected.
- **Immediate next step:** first push to `development` (nothing committed yet; repo has 0 commits) triggers
  ci + deploy-int; approve the issue; then verify with a real client (ID server jkr.jayarajnarayanan.in:22116,
  relay :22117 for int, key from run summary). Int ports are 22xxx and NOT open in the SG (optional) -
  open TCP 22115-22119 + UDP 22116 only if testing int from outside the node.
- **INT DEPLOYED + CLIENT TEST PASSED (2026-10-31):** deploy-int succeeded on the real cluster (jkr-int,
  ports 22115-22119, SG opened for them). Two PCs (192.168.0.108, 192.168.0.104) connected and
  remote-controlled each other through `jkr.jayarajnarayanan.in:22116/22117` using `scripts/client-setup.ps1
  -IdPort 22116 -RelayPort 22117 -Key <int key>`. This verifies hostNetwork on Cilium, EBS PVC, SG, DNS.
- **Branch model:** `development` -> deploy-int (auto) ; `main` -> prod only. `deploy-prod.yml` has a `guard`
  job that fails unless run from `main`; ci runs on both. Edits made locally, NOT yet committed/pushed.
  deploy-prod was not visible in the Actions list (not yet registered); expected to appear after a push.
- **✅ PROD DEPLOYED + VERIFIED (2026-10-31):** deploy-prod ran from `main`, jkr-prod live on
  `jkr.jayarajnarayanan.in` ports 21115-21119; user connected a remote computer through it.
  Server side (M1 + CI/CD) is DONE. (Confirm with user that the prod private key was backed up.)
- **NOW: M2 (client = JustKeepRemote).** Plan, in order:
  1. Recon (read-only): where RustDesk 1.5.1 defines app name, icons, default server/key
     (`libs/hbb_common` config `RENDEZVOUS_SERVERS`, `RS_PUB_KEY`, `APP_NAME`), and the phone-home calls
     (`version_check_request`, `check_software_update`, api.rustdesk.com / public-server calls).
  2. Bake server + prod key via build-time config (hbb_common/src/config.rs defaults or `custom-rendezvous-server`
     options), so a fresh install needs no setup script.
  3. Rebrand: APP_NAME, window titles, exe name, icon (flutter/windows/runner resources), strings.
  4. Remove client phone-home (update check + any api.rustdesk.com calls); keep patches as a reviewable patch
     file applied in CI against a pinned RustDesk 1.5.1 SHA (do not edit vendor/ in place un-recorded).
  5. Build client in GitHub Actions (windows runner; ~1h+ cold, cache vcpkg) and publish exe zip as a release asset.
  6. Then M6: Windows service install (UAC/login screen, unattended), installer + code signing.
  **M2a STATUS (2026-10-31):** recon done (sub-agent + own greps: no other hosts: no STUN, no analytics).
  Wrote `client/apply-jkr-patches.ps1 -Key <prod pubkey> [-DryRun]` = anchored, idempotent edits to
  vendor/rustdesk (hbb_common is a submodule): PROD_RENDEZVOUS_SERVER + RENDEZVOUS_SERVERS = host,
  RS_PUB_KEY = prod key, APP_NAME = JustKeepRemote (=> custom client: new config dir/service/install dir,
  update UI off), version-check URL "", do_check_software_update no-op, get_api_server returns "" (kills
  heartbeat/sysinfo/audit that would hit <host>:21114), admin.rustdesk.com fallback removed.
  DryRun against pinned checkout (rustdesk 04360797, hbb_common fae47e0): all 8 anchors OK. NOT applied yet:
  APPLIED 2026-10-31 with prod key WBQWPJXUFJcOp+ndfi9d6B+IOh719m5PNsa+45G6H0s= (public, not secret).
  ✅ M2 build #1 SUCCEEDED (10:14, ~25 min): rustdesk.exe + librustdesk.dll (38 MB) in
  vendor/rustdesk/flutter/build/windows/x64/runner/Release. Binary string scan of librustdesk.dll: contains
  jkr.jayarajnarayanan.in and the prod key; contains NO api.rustdesk.com, admin.rustdesk.com,
  rs-ny.rustdesk.com or the old RustDesk public key. ("JustKeepRemote" not found as plain ASCII - probably
  inlined/UTF-16; verify at runtime via the %APPDATA%\JustKeepRemote folder.) NOT yet runtime-tested:
  ✅ RUNTIME TESTED (user, 2026-10-31): two PCs connected with the M2 build and NO setup script;
  %APPDATA%\JustKeepRemote exists (rename works). Network check on 192.168.0.108: the rustdesk process
  (pid 3088) had zero TCP connections and one UDP socket; every other ESTABLISHED line belonged to other
  apps (AnyDesk, Chrome, Kiro, Freelens->54.81.13.170:6443 = k8s API via freelens-k8s-proxy, not rustdesk).
  => no connection to any *.rustdesk.com. M2a DONE. (UDP remote addresses not visible via netstat; the
  apply script + string scan show the update/admin URLs are gone.)
  M2b (2026-10-31) WRITTEN + APPLIED, build #2 started (log scripts/build-client-m2b.log):
  - `client/branding/make-icons.ps1` generates placeholder "JKR" icons (blue gradient rounded square, white text,
    user has no logo) into client/branding/out (committed); apply script copies them to res/*.ico|png,
    runner app_icon.ico, flutter/assets/icon.png. Replace the output with real artwork anytime.
  - apply-jkr-patches.ps1 now also: locks custom-rendezvous-server/key/relay-server/api-server via
    OVERWRITE_SETTINGS (Settings > Network becomes read-only), tab-bar title, "About JustKeepRemote",
    privacy/website/powered-by/install/public-server links -> https://github.com/jayarajito/ultraviewer,
    en.rs "RustDesk" -> JustKeepRemote (23 strings; OTHER languages still say RustDesk), exe ProductName/
    FileDescription (Runner.rc, Cargo winres). KEPT upstream CompanyName/LegalCopyright and the About-page
    "Purslane Tech" copyright: AGPL requires preserving upstream notices.
  - Edit-Line idempotency fixed (applied = new text present AND old anchor gone).
  ✅ M2b BUILD SUCCEEDED (11:33). Build #2 first failed with LNK1104 because the old rustdesk.exe was still
  RUNNING (locked flutter/build, and scripts' silent delete hid it). LESSON: stop rustdesk.exe before any rebuild;
  build-client script should do `Get-Process rustdesk | Stop-Process` first (TODO). Exe now reports
  ProductName "JustKeepRemote". Awaiting user visual/runtime check.
  PACKAGING (2026-10-31): `scripts/package-client.ps1` -> dist/JustKeepRemote-1.5.1-win-x64.zip (32 MB,
  +.sha256; dist/ gitignored). Exe shipped as JustKeepRemote.exe (+README.txt). shortpath-build.ps1 now stops
  running clients before building (fixes the LNK1104 lesson). M6 = RustDesk's built-in "Install" button
  (service named JustKeepRemote, %ProgramFiles%\JustKeepRemote, needs UAC) - NOT yet tested by user:
  test plan = install on 104, set permanent password, reboot, connect before login, open an elevated app and
  confirm UAC prompt is controllable. M2c (CI build of client + GitHub release) still TODO: cold build ~1h+ on
  windows-latest, needs vcpkg cache, Flutter 3.24.5 + frb 1.80.1 + VS patch; do after M6 test passes.
  ✅ M6 TESTED by user (2026-10-31): Install + permanent password; connected to the machine after a REBOOT
  (login-screen access works). UAC-prompt control not explicitly reported.
  M2c WRITTEN (not run on GitHub): `.github/workflows/client-build.yml` (manual; jobs check-inputs -> bridge
  (ubuntu, Flutter 3.22.3, frb 1.80.1) -> build (windows-2022: pinned upstream rustdesk 04360797 + hbb_common
  fae47e0, apply-jkr-patches, Flutter 3.24.5, Rust 1.75, vcpkg 9e593bb with HOST triplet x64-windows-static,
  dir-based vcpkg cache, C:\rd junction, build.py --flutter --hwcodec, verify-client, package-client) ->
  optional DRAFT prerelease). Upload artifact `JustKeepRemote-windows-x64`. actionlint clean.
  Deliberately NOT done vs upstream CI: custom Flutter engine download (rustdesk/engine) and the dropdown
  patch; no RustDeskTempTopMostWindow broker (privacy mode feature untested). Key/host are hardcoded env
  (public values). `scripts/verify-client.ps1` = static ship checks (passes on local build).
  RISKS: Rust 1.75 vs local 1.99 never compared; first CI run will likely need iteration (cold ~1.5-3h).
  TODO next: user runs client-build once (Actions > Build client (Windows) > Run workflow, release OFF first);
  then code signing / MSI installer decision; translate other languages; privacy-mode broker; auto-update (own).
  ✅ M2c FIRST CI RUN GREEN (2026-10-31, branch development, run 41201987866): bridge + build jobs
  succeeded, "Build and package" 1h04m (Build the client 33m37s), verify-client + package + artifact upload
  all passed in CI (so the CI-built dll has our host/key and none of the RustDesk hosts). Release job was
  skipped (release off). NEXT: user downloads artifact `JustKeepRemote-windows-x64`, runs it on a clean PC to
  confirm it behaves like the local build; then re-run with release ON + tag v0.1.0 -> draft release.
  The CI zip is not code-signed. Second run should be faster (vcpkg + cargo caches now exist).
  ✅ CI-BUILT ZIP USER-TESTED (2026-10-31): downloaded artifact from run 41201987866 Summary > Artifacts,
  installed, remote access works. CI build = trustworthy. NEXT: run client-build with release ON, tag v0.1.0
  (draft prerelease) and publish after review; then prod-key backup check, README/user guide, own update
  check, other-language strings, signing decision.
  ✅ RELEASE v0.1.0 CREATED by user (2026-10-31, tag at commit 9326144; user said "completed"; draft vs
  published state not confirmed). Added root README.md + LICENSE (AGPL-3.0 text from gnu.org) - NOT yet
  committed. NOTE: GitHub repo shows as PRIVATE (lock icon): AGPL requires offering source to the users who
  receive the binary, so before distributing to anyone outside the owner, make the repo public (or give them
  source access). Open items: own update check, other-language strings, code signing/MSI, prod-key backup
  confirmation, int env cleanup optional.
  ✅ v0.1.0 PUBLISHED-ish; prod key backup CONFIRMED by user.
  v0.2.0 (IN PROGRESS, 2026-10-31): two features requested by user:
  (1) UPDATE CHECK against our own GitHub releases: `client/src/jkr_update_logic.rs` (pure, 6 unit tests via
  scripts/test-update-logic.ps1, also run in ci.yml job client-update-logic) + `client/src/jkr_update.rs`
  (GET api.github.com/repos/<Repo>/releases, 12h re-check, respects enable-check-update, sets
  SOFTWARE_UPDATE_URL + pushes check_software_update_finish; only accepts URLs under
  https://github.com/<Repo>/releases/). Reuses the existing home-screen banner; button opens the release page;
  NO auto-download/install. Version source = `client/VERSION` (0.2.0), compiled in via @JKR_VERSION@; the
  workflow now REQUIRES release_tag == v<VERSION>. Package zip is now named JustKeepRemote-<VERSION>-win-x64.
  CAVEAT: anonymous GitHub API sees nothing while the repo is PRIVATE (404 -> silently "no update"); repo must
  be public for the check to work. v0.1.0 builds have no checker, so only >=0.2.0 installs will notice updates.
  (2) MINIMIZE HIDES THE WINDOW: minimize button on the MAIN window calls windowManager.hide() instead of
  minimize, only when installed (tray icon exists, tray "Open"/click brings it back), stop-service != Y and
  option `hide-on-minimize` != N (checkbox "Hide window when minimized" in Settings > General, installed
  Windows only). Portable runs keep normal minimize (no tray => window would be lost). Taskbar-click/Win+D
  minimize unchanged. Incoming-connection window (CM) unaffected. NOT a stealth mode: the tray icon stays.
  apply-jkr-patches.ps1 now supports multi-line anchors (LF/CRLF), -Repo, reads client/VERSION; verified:
  all anchors match on a PRISTINE vendor checkout (reset via git checkout in vendor/rustdesk + hbb_common),
  second run skips every code edit. Local build log scripts/build-client-v020.log. NEXT: verify build, user
  tests (banner needs a published release > 0.2.0 and a public repo), commit, run client-build with
  release_tag v0.2.0.
  ✅ v0.2.0 LOCAL BUILD OK (2026-10-31 20:51): Rust (incl. new modules) compiled first time, Flutter built,
  verify-client ALL PASS (incl. new update-check + version checks), package dist/JustKeepRemote-0.2.0-win-x64.zip
  (32 MB). NOT yet run by the user; NOT yet committed; CI run with release_tag v0.2.0 not yet done.
  Files to commit: client/{VERSION,src/*,apply-jkr-patches.ps1}, scripts/{package-client,verify-client,
  test-update-logic}.ps1, .github/workflows/{client-build,ci}.yml, README, steering.
  REBUILT 21:05 with 2 more UI patches: Settings > General now shows "Check for software update on startup"
  (was hidden for custom clients, so users could not opt out) and hides upstream's useless "auto update"
  switch. Final zip sha256 d7cec0ab...3c08 (32 MB), verify-client ALL PASS. apply script now skips unchanged
  files (a rewrite bumps mtime => ~9 min cargo rebuild).
  OPEN DECISION (user asked to embed a GitHub PAT in the client so the update check can read the PRIVATE repo):
  NOT implemented. Reason: a token compiled into a distributed exe is extractable with `strings`; it would give
  anyone with a copy read access to the private source, expires (fine-grained max 1y => rebuild/redistribute),
  and cannot be revoked per-user. Recommended instead: (A) make repo public (AGPL expects source to be available
  to recipients anyway), or (B) keep source private and publish only the release zips to a separate PUBLIC
  releases-only repo (client checks that repo, no token in the client; workflow pushes with a PAT kept as a
  GitHub secret), or (C) static version.json on own host. Awaiting user's choice. If user still wants the PAT:
  fine-grained, this repo only, Contents:read only, short expiry, injected from a GitHub secret at build time.
  Minimize question: hide-on-minimize already implemented (see above); awaiting user test on an INSTALLED copy.
  TEST PLAN: (a) minimize hides the window ONLY on an INSTALLED copy; tray icon/Open restores; checkbox in
  Settings > General turns it off; portable copy minimizes normally. (b) update banner can only be proven once
  the repo is public AND a release newer than the running version is published (e.g. run 0.2.0, publish 0.2.1).
  TO VERIFY after build: icon/title/About text, Settings > Network greyed out, still "Ready" + connects.
  NEXT: M2c CI client build + release asset; then M6 service/installer.
  Next after apply: rebuild via scripts/shortpath-build.ps1 (C:\jkr; ~15-60 min incremental), run the exe on a
  clean profile with NO setup script, expect "Ready"; check no traffic to *.rustdesk.com (netstat/log).
  M2b (after): icons (res/*.ico, runner app_icon.ico), Runner.rc/Cargo winres strings, tabbar_widget.dart
  title + "About RustDesk" + rustdesk.com links, lang strings; lock settings (OVERWRITE_SETTINGS) so users
  cannot change server; M2c: CI client build + GitHub release asset; AGPL: publish modified source (keep
  vendor changes reproducible via this script, record upstream SHAs).
  Constraints: AGPL -> publish source of modified client; keep build recipe from tech-stack.md (Flutter 3.24.5,
  static ffmpeg triplet, frb 1.80.1, VS18 patch or VS2022, short build path).
- **Next:** M2 branding, bake server+key into client, remove client phone-home (hbb_common
  version_check_request); M6 Install/service for UAC + unattended access.
- Repo is `jayarajito/ultraviewer` (0 commits tracked yet); `.gitignore` now excludes vendor/, existingapp/, tools/.

### âœ… M0 DONE (2026-10-29) â€” BIDIRECTIONAL remote control verified across 2 PCs
- Self-hosted server (hbbs+hbbr) in Docker on **192.168.0.108** with pinned key.
- Client built 100% from source (RustDesk 1.5.1, Flutter 3.24.5, HW codecs).
- **End-to-end PROVEN both directions** between two real machines on the LAN:
  - A = 192.168.0.108, RustDesk ID **221 266 011** (docker host + partner)
  - B = 192.168.0.104, RustDesk ID **156 675 859** (controller)
  - Bâ†’A and Aâ†’B both connect + control through OUR server. 
- **The unmodified RustDesk base runs end-to-end under our own infrastructure.**

### Gotchas solved during the 2-PC test (all documented for prod/K8s)
- Settings UI silently fails to persist custom server â†’ write config directly.
  Helper scripts kept: `set-server.ps1` (this host), `client-setup.ps1` (any client:
  tests reachability + writes %APPDATA%\RustDesk\config\RustDesk2.toml).
- BOTH peers must use the SAME real relay IP (192.168.0.108), NOT 127.0.0.1, or the
  relay address handed out is unusable by the other peer.
- Windows Firewall: open TCP 21115-21119 + UDP 21116. MUST run elevated; `IsAdmin`
  check matters. `open-firewall.ps1` (Profile Any) + `set-network-private.ps1`.
  Network was "Public" (blocks inbound) â†’ set to Private.
- Both clients must be RUNNING to be registered with hbbs before connecting.
- FULL control of UAC/login screen on the partner needs Install (SYSTEM service) â†’
  deferred to M6. Normal desktop control works without Install.

---
## (history below)
## Earlier status line: M0 in progress â€” server UP, client deps building

### ðŸš§ M0 â€” session on 2026-10-28 (continued)
- âœ… **Full client toolchain verified** (see `tech-stack.md` â†’ "Verified toolchain"):
  - Flutter 3.47.8 / Dart 3.13.7, Rust 1.99.1 (stable-x86_64-pc-windows-msvc),
    CMake 4.5.0, MSVC cl 19.51, Ninja (via VS), LLVM/Clang 23.1.4 + libclang.
  - vcpkg 2026-09-26 bootstrapped at `C:\Users\JAYARAJ\vcpkg\vcpkg`.
  - **NASM was missing** â†’ installed project-local to `tools\nasm-2.16.03` (gitignored).
  - **Sciter NOT needed** â€” we build the Flutter UI, not the legacy Sciter UI.
- âœ… Created `scripts/env.ps1` â€” dot-source to assemble build env (VS DevShell +
  VCPKG_ROOT + LIBCLANG_PATH + NASM) without touching system PATH.
- âœ… Cloned **RustDesk client 1.5.1** â†’ `vendor/rustdesk` (+ `hbb_common` submodule).
- ðŸš§ Created `scripts/install-deps.ps1` and **started vcpkg dependency install**
  (manifest mode, `x64-windows-static`): aom, libvpx, libyuv, opus, libjpeg-turbo,
  ffmpeg (nvenc+qsv+amf). Running in background; log at `scripts/install-deps.log`.
  This is the long step (ffmpeg/aom compile from source).

### ðŸ–¥ï¸ Server (from earlier this session) â€” still valid
- `server/docker-compose.yml`: `jkr-hbbs` + `jkr-hbbr` verified running.
- **Dev server public key fingerprint:** `rKb+EardRcZ3Ugu3+76zh+vqvwMj67z8O+zNnKi8TtM=`
  (private key `server/data/id_ed25519`, gitignored).

### âœ… vcpkg dependencies â€” DONE (59 min build)
- All 34 packages installed to `x64-windows-static`. Verified libs present:
  aom, vpx, yuv, opus, jpeg/turbojpeg (+ ffmpeg avcodec/avformat/avutil with
  NVENC/QSV/AMF/NVDEC hardware codecs enabled). Log: `scripts/install-deps.log`.
- Created `scripts/build-client.ps1` (env + `flutter pub get` +
  `python build.py --flutter --hwcodec --skip-portable-pack`).

### â›” BLOCKER â€” Windows Developer Mode required
- `flutter pub get` succeeded but flagged: **"Building with plugins requires
  symlink support. Please enable Developer Mode."**
- Flutter Windows builds need Developer Mode ON (symlink support for plugins).
- `file_picker` default-plugin warnings are NON-fatal; ignore them.
- **User action needed:** enable Developer Mode via `start ms-settings:developers`
  (or set HKLM\...\AppModelUnlock\AllowDevelopmentWithoutDevLicense=1 as admin).
  Not auto-enabled â€” it loosens app-install security, so it's the user's call.

### ðŸš§ Client build attempt #1 â€” FAILED on hwcodec (ffmpeg triplet), fix underway
- Developer Mode enabled (verified: AppModelUnlock=1). Ran `build-client.ps1`.
- Cargo compiled ~hundreds of crates fine, then **`hwcodec` build script failed**:
  `fatal error C1083: Cannot open include file 'libavcodec/avcodec.h'`.
- **Root cause:** hwcodec's build.rs hard-codes the vcpkg triplet
  `x64-windows-static` and links `avcodec/avutil/avformat/libmfx` statically from
  `$VCPKG_ROOT/installed/x64-windows-static`. But our manifest install placed
  **ffmpeg only in `x64-windows` (dynamic)** â€” the static tree had no libav* headers.
- **Fix:** `scripts/install-ffmpeg-static.ps1` installs
  `ffmpeg[amf,nvcodec,qsv]:x64-windows-static` + `mfx-dispatch:x64-windows-static`
  in CLASSIC mode (run from neutral dir, using RustDesk's overlay ports/triplets).
  Running now; log `scripts/install-ffmpeg-static.log`.
- LESSON for K8s/prod build image: always install the static-triplet ffmpeg
  explicitly; the manifest's conditional static entry is not sufficient for hwcodec.

### âœ… Static ffmpeg fix WORKED â€” hwcodec + librustdesk link passed
- `scripts/install-ffmpeg-static.ps1` completed (19 min); `avcodec.h` now in
  `x64-windows-static\include`. Rebuild cleared the hwcodec C1083 error and the
  main `rustdesk` crate compiled + started linking without ffmpeg link errors
  (only harmless LNK4099 libsodium PDB warnings).

### ðŸš§ Client build attempt #2 â€” FAILED on missing Flutter-Rust bridge
- New error: `error[E0583]: file not found for module bridge_generated`
  (`src/lib.rs:39`), cascading into many `EventToUI: IntoIntoDart` errors.
- **Root cause (confirmed via RustDesk `AGENTS.md` + CI `bridge.yml`):** the
  Flutter-Rust bridge files are **gitignored and NOT shipped** in the repo:
  `src/bridge_generated.rs`, `src/bridge_generated.io.rs`,
  `flutter/lib/generated_bridge.dart` (+ `.freezed.dart`). CI regenerates them;
  `build.py` does NOT generate them on Windows. So our clone lacks them.
- **Fix:** `scripts/generate-bridge.ps1` installs the pinned codegen and runs it:
  - `cargo install cargo-expand --version 1.0.95 --locked`
  - `cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked`
  - `flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs
     --dart-output ./flutter/lib/generated_bridge.dart
     --c-output ./flutter/macos/Runner/bridge_generated.h`
  Running (log `scripts/generate-bridge.log`). Status 2026-10-28 late:
  cargo-expand 1.0.95 installed OK; flutter_rust_bridge_codegen 1.80.1 still
  downloading its (large, older) dependency set â€” network is slow on this box,
  so this step is taking a long time but is progressing with no errors.
- CRITICAL LESSON for K8s/prod build image: the pipeline MUST run bridge codegen
  (frb 1.80.1, needs cargo-expand 1.0.95) before `build.py`. Pin these versions.
  Pre-bake these tools into the build image so prod builds don't re-download.
- TOOLING NOTE: the interactive execute_pwsh shell in this env intermittently
  corrupts (PSReadLine buffer bug); use background processes + grep/read_file
  to monitor instead.

### âœ… Bridge generation â€” DONE
- `scripts/generate-bridge.ps1` succeeded: frb codegen 1.80.1 ran, "Success!",
  `src/bridge_generated.rs` (+ .io.rs, generated_bridge.dart/.freezed.dart) created.
- The frb_codegen install was slow (large older dep set + slow network) but clean.

### ðŸš§ Client build attempt #3 â€” running
- Re-ran `scripts/build-client.ps1` (log `scripts/build-client3.log`). Now has:
  static ffmpeg âœ…, bridge files âœ…. Expect: cargo lib â†’ `librustdesk.dll`, then
  `flutter build windows --release` â†’ `rustdesk.exe`.

### ðŸš§ Build #3 â€” past both prior failures; main crate compiling (slow)
- `flutter pub get` âœ…, cargo resumed, hwcodec âœ… (static ffmpeg worked),
  bridge âœ… (no E0583). Reached `Compiling rustdesk v1.5.1` (the main crate).
- The main `rustdesk` crate is a VERY large release-mode compile. Diagnosed via a
  process probe (`scripts/probe-link.ps1`): `rustc` alive with 260s+ CPU and
  climbing â€” compiling, NOT stalled, NOT yet linking (no link.exe spawned, no
  artifacts in target/release yet). Just slow. Let it run.
- Monitoring technique that works in this env: background-process sleeps +
  `scripts/status.ps1` (disk check) + `scripts/probe-link.ps1` (CPU check);
  the interactive shell and live process buffers are unreliable here.

### âœ… Rust core BUILT â€” `librustdesk.dll` 38 MB produced
- The entire Rust side (core + hwcodec + static ffmpeg + bridge) compiled and
  linked cleanly. `target/release/librustdesk.dll` exists (38 MB). Big milestone.

### â›” BLOCKER â€” Flutter SDK too new for RustDesk 1.5.1 Dart code
- `flutter build windows --release` failed in Dart compile, not Rust:
  - `common.dart`: `TabBarTheme` not assignable to `TabBarThemeData?`;
    `DialogTheme` not assignable to `DialogThemeData?`.
  - `google_fonts-6.2.1`: constant evaluation error.
  - â†’ MSB8066 (flutter_assemble custom build exited 1).
- **Root cause:** installed **Flutter 3.47.8** is far newer than what RustDesk
  1.5.1 targets. RustDesk CI (`.github/workflows/bridge.yml`) uses **Flutter
  3.24.5** (bridge gen on 3.22.3). Newer Flutter renamed Material theme classes
  (TabBarThemeâ†’TabBarThemeData, DialogThemeâ†’DialogThemeData), breaking 1.5.1's UI.
- **Decision needed (options):**
  A. Install Flutter 3.24.5 alongside (via a second SDK dir or FVM) and build
     the UI with it. Rust core already built; only the Flutter step reruns.
     RECOMMENDED â€” matches upstream, lowest risk.
  B. Patch RustDesk's Dart (common.dart etc.) to the new Material API + bump
     google_fonts. More invasive; diverges from upstream.
- NOTE: the bridge was generated with frb 3.22.3-era too, so 3.24.5 is consistent.

### âœ… Option A chosen â€” Flutter 3.24.5 installed project-local
- `scripts/get-flutter.ps1` downloaded flutter_windows_3.24.5-stable.zip to
  `tools/flutter-3.24.5` (gitignored). `Expand-Archive` (PS 5.1) FAILED partway on
  the huge archive â†’ switched to `scripts/extract-flutter.ps1` using **tar.exe**
  (bundled bsdtar), which extracted cleanly. LESSON: never use Expand-Archive for
  the Flutter SDK; use tar.exe.
- `scripts/env.ps1` updated: prepends the project-local Flutter 3.24.5 to PATH so
  it shadows the global 3.47.8. Global Flutter untouched.

### ðŸš§ Build #4 FAILED (stale CMake cache) â†’ fix added â†’ build #5 running
- Build #4: Flutter 3.24.5 pub get OK, but `flutter build windows` hit
  `CMake Error: generator Visual Studio 16 2019 does not match ... 18 2026`.
  Cause: leftover `flutter/build` CMake cache from the earlier 3.47.8 build.
- FIX: `build-client.ps1` now deletes `flutter/build` before pub get (added a
  clean step). LESSON: switching Flutter/VS generators requires wiping flutter/build.
- Build #5 (`build-client5.log`) running with that fix + Flutter 3.24.5.

### ðŸš§ Build #5 FAILED (VS generator) â†’ patched Flutter â†’ build #6
- Build #5: stale-cache fix worked, but new CMake error:
  `Generator "Visual Studio 16 2019" could not find any instance of Visual Studio`.
- Cause: Flutter 3.24.5 only maps VS major 17â†’"VS 17 2022"; everything else
  (incl. our VS 18 / 2026) falls back to "VS 16 2019", which isn't installed.
  Found in `flutter_tools/lib/src/windows/visual_studio.dart` `cmakeGenerator`.
- FIX: patched that switch to add `18 => 'Visual Studio 18 2026'`, then deleted
  `flutter_tools.stamp`/`.snapshot` (`scripts/reset-flutter-snapshot.ps1`) so the
  tool recompiles with the patch. LESSON for build image: either install VS 2022
  build tools, or apply this one-line Flutter patch. (Prefer the patch; it's pinned.)
- Build #6 (`build-client6.log`) running.

### ðŸš§ Build #6 got PAST CMake (VS patch worked) but FAILED in plugin compile
- VS 2026 generator patch worked â€” CMake generated, Flutter app started compiling.
- Failed compiling plugin `flutter_gpu_texture_renderer`:
  `C1083: Cannot open include file 'include/.../..._plugin_c_api.h'` and
  `MSB6003 ... DirectoryNotFoundException ... .dir\Release\flutter_.2CFFA38F.tlog`.
- **Root cause:** the repo lives under a LONG OneDrive path
  (`C:\Users\JAYARAJ\OneDrive\Development\Projects\UltraviewerClone\ultraviewer`).
  Flutter's plugin build creates very deep intermediate paths (`.dir\Release\*.tlog`)
  that exceed Windows MAX_PATH (260) and OneDrive's reparse handling breaks symlinks.
- **FIX:** `scripts/shortpath-build.ps1` creates a directory JUNCTION `C:\jkr` ->
  repo and runs the whole build from `C:\jkr` (short paths), no files moved.
  LESSON for build image/CI: build from a short path (e.g. C:\jkr or C:\src), never
  from a deep OneDrive-synced directory.
- Build #7 (`build-client7.log`) running via C:\jkr.

### âœ…âœ… CLIENT BUILT â€” `rustdesk.exe` produced (build #7, short path)
- Short-path fix (C:\jkr junction) cleared the plugin MAX_PATH/OneDrive error.
  Flutter build finished: "Built build\windows\x64\runner\Release\rustdesk.exe" (336s).
- Full runnable output at
  `vendor\rustdesk\flutter\build\windows\x64\runner\Release\`:
  rustdesk.exe + librustdesk.dll + flutter_windows.dll + all plugin DLLs
  (gpu_texture_renderer, desktop_multi_window, screen_retriever, custom_cursor,
  texture_rgba_renderer, window_manager, ...) + data/.
- **M0 BUILD PHASE COMPLETE** â€” the unmodified RustDesk 1.5.1 base compiles from
  source on this machine (server + client), with HW codecs. Base proven.

### ðŸ”‘ Full reproducible build recipe (for K8s image / CI) â€” all verified
1. Toolchain: Rust (MSVC), VS2026 BuildTools, LLVM/Clang, CMake, NASM, vcpkg,
   Flutter **3.24.5** (NOT newer), Docker.
2. vcpkg static deps (x64-windows-static) incl. ffmpeg[amf,nvcodec,qsv] +
   mfx-dispatch â€” MUST be the static triplet (hwcodec links them statically).
3. Generate FRB bridge: cargo-expand 1.0.95 + flutter_rust_bridge_codegen 1.80.1
   (feature uuid), run codegen â†’ src/bridge_generated.rs etc.
4. Patch Flutter visual_studio.dart: add `18 => 'Visual Studio 18 2026'`; reset
   flutter_tools snapshot. (Or install VS2022 build tools instead.)
5. Build from a SHORT path (C:\jkr junction) to avoid MAX_PATH/OneDrive.
6. `python build.py --flutter --hwcodec --skip-portable-pack`.

### âœ… Client runs + registers with our server
- Ran rustdesk.exe (portable). Set Settings > Network > ID/Relay server to our
  server + pinned key; bottom-left shows green **"Ready"** = registered with our
  self-hosted hbbs. Server containers still up (4h).
- This machine LAN IP: **192.168.0.108** (Ethernet). 172.x are virtual adapters.
- Install NOT required for the test; Install only needed for UAC/secure-desktop
  control + unattended access (deferred to M6). Portable run is fine for M0.

### ðŸ§ª End-to-end test instructions (user-driven, GUI)
- Copy ENTIRE `...\x64\runner\Release\` folder (exe + all DLLs + data\) to a 2nd
  Windows PC on the same LAN; no install needed. Zip the folder, unzip, run.
- On the 2nd PC set ID+Relay server = **192.168.0.108**, same Key. Expect "Ready".
- Connect from one to the other using the shown ID + one-time password; verify
  screen view + mouse/keyboard control. (UAC/login-screen control needs Install â†’ M6.)
- Ensure firewall allows server ports 21115-21119 on 192.168.0.108.

### âœ… 2-machine bidirectional control PASSED (user confirmed) â€” M0 fully done.

### âœ… SERVER built from source too (2026-10-29)
- Cloned `rustdesk-server` (v1.1.17) â†’ `vendor/rustdesk-server` (+ hbb_common submodule).
- Pure Rust, no vcpkg/ffmpeg/Flutter. Built via `scripts/build-server.ps1`
  (sources env.ps1 for MSVC toolchain, `cargo build --release`). Slow network/machine
  made it long, but clean.
- Produced + verified: `hbbs.exe` (6 MB), `hbbr.exe` (3 MB), `rustdesk-utils.exe`
  in `vendor/rustdesk-server/target/release`. `hbbs.exe --help` runs â†’ "hbbs 1.1.17".
- **We now own the ENTIRE stack from source: client (rustdesk.exe/librustdesk.dll)
  AND server (hbbs/hbbr/rustdesk-utils).**
- `scripts/run-server-native.ps1` runs the from-source server binaries natively
  (no Docker), reusing server/data keypair. For K8s we can containerize these.

### ðŸš§ M1 â€” containerize + K8s (started 2026-10-29)
**Production cluster facts (read-only inspection; NOTHING applied):**
single kubeadm control-plane node `ip-10-0-15-237` on AWS, Ubuntu, containerd 2.3,
Cilium CNI, EBS CSI. StorageClasses: `ebs-gp3` (default, Delete) and
`ebs-gp3-database` (Retain). No node taints. **No LoadBalancer implementation.**
It is SHARED with other real workloads (my-cv-prod, lotto-int, postgresql,
monitoring) -> treat as production: never `kubectl apply` without explicit user OK.

**Done:**
- `server/Dockerfile`: multi-stage, builds hbbs/hbbr/rustdesk-utils from
  `vendor/rustdesk-server` on rust:1-bookworm -> debian:bookworm-slim, non-root uid
  10001, HOME=/data, bundled static libsodium, rustls (no OpenSSL needed at runtime).
  `server/Dockerfile.dockerignore` excludes the multi-GB Windows `target/`.
- `scripts/build-server-image.ps1` (waits for Docker engine; tags jkr-server:0.1.0 + :dev).
- **Privacy patch (build-time, default ON, `--build-arg DISABLE_UPDATE_CHECK=1`):**
  upstream hbbs calls `check_software_update()` unconditionally -> POSTs OS name/version,
  arch and a persistent hardware fingerprint to api.rustdesk.com every 24h. Removed via
  sed on the image's COPY of main.rs; build fails if the patch doesn't apply; vendor/
  stays pristine. **TODO M2: the CLIENT has the same phone-home (hbb_common
  version_check_request) - remove/redirect it too.**
- `k8s/` (kustomize): namespace `justkeepremote`, PVC `jkr-server-data` (1Gi, Retain
  class), Deployment `jkr-server` = hbbs+hbbr in ONE pod, hostNetwork, Recreate,
  `-k _` on both, hbbr waits for hbbs to create the key (no first-start race),
  non-root + read-only rootfs + caps dropped, tcp probes, resource limits.
  ConfigMap `RELAY_HOST` placeholder: pod REFUSES to start until edited.
- Validated OFFLINE: `kubectl kustomize` renders 4 resources; kubeconform strict
  (k8s 1.30 schemas): 4 valid / 0 invalid (`scripts/k8s-render.ps1`).
- `k8s/README.md`: checklist, image delivery (registry or `ctr -n k8s.io images import`),
  key read-out + BACKUP, rollback. Root `.gitignore` added (secrets, target/, build/).
- `scripts/client-setup.ps1` now takes `-Key` (default = dev key) for prod use.

**Why hostNetwork:** no LB exists; NodePort can't serve fixed 21115-21119 (+UDP 21116);
hostNetwork also gives hbbs real client IPs (Docker NAT showed 172.20.0.1 for all).
**=> AWS security group must allow TCP 21115-21119 + UDP 21116 (NOT verified).**

**Image BUILT + VERIFIED (2026-10-30):** `jkr-server:0.1.0` (= `:dev`), linux/amd64
(matches the node), 140 MB. `scripts/smoke-test-server-image.ps1` -> 16/16 PASS, run
the way K8s will (non-root, read-only rootfs, caps dropped, `-k _`): no missing libs;
listens 21115/21116/21117; advertises the `-r` relay; key created 0600 owned by 10001;
SAME key after restart; privacy patch proven by control (unpatched Windows hbbs.exe
contains `api.rustdesk.com`, patched Linux hbbs does not).

**Dev server now runs OUR image** (`server/docker-compose.yml`, `scripts/dev-server-up.ps1`):
named volume `jkr-dev-data` seeded with the existing dev keypair (clients unaffected;
log shows `Key: rKb+EardRc...`), relay advertised as 192.168.0.108:21117, hardened,
`-k _`. Old setup kept for revert: `server/docker-compose.upstream.yml`
(`docker compose -f docker-compose.upstream.yml up -d`). Status: `scripts/dev-server-status.ps1`.
Why a volume not ./data: the server enforces 0600 on the private key; Windows bind
mounts can't honour that.

**Build gotchas found (keep!):**
- sqlx `query!` checks SQL at COMPILE time against the committed `db_v2.sqlite3` via
  `.env` (DATABASE_URL). Excluding them from the build context => "unable to open
  database file". They must stay in the context (build stage only; never in runtime).
- Windows PowerShell 5.1: native-command stderr is a terminating error under
  `$ErrorActionPreference='Stop'` (e.g. `docker volume inspect` on a missing volume).
- Linux hbbs logs `Listening on tcp/udp [::]:21116` (bind addr included); default bind
  is all interfaces dual-stack `[::]`.
- Long one-liners crash this shell's PSReadLine; write a .ps1 and run it. Background
  "sleep" terminals return immediately - use a blocking `Start-Sleep` to actually wait.

**NOT verified (be honest about these):**
1. Real clients against the new dev server with `-k _` (needs the user: start RustDesk on
   192.168.0.108 and 192.168.0.104, expect "Ready", then connect both ways).
2. Anything on the real cluster: hostNetwork + Cilium + UDP 21116, EBS PVC bind, the
   AWS security group (TCP 21115-21119, UDP 21116), image import on containerd.
3. Production key: generated in-cluster on first start - not created yet.

### ðŸ›‘ Needs USER decisions before deploying k8s/ (prod, shared cluster)
- **Go-ahead + window** to `kubectl apply -k k8s/` (I will not apply on my own).
- **RELAY_HOST**: public DNS name / Elastic IP of the node (edit k8s/kustomization.yaml).
- **AWS security group** open for TCP 21115-21119 + UDP 21116.
- **Image delivery**: registry (ECR?) or `ctr -n k8s.io images import` on the node.
- Back up `/data/id_ed25519` right after first start (see k8s/README.md).

### â­ï¸ Next
1. User: real-client test on the dev server (above). Tell me the result.
2. User decisions above -> deploy k8s/ together, then read prod pubkey.
3. M2: JustKeepRemote customization (branding, baked-in server+key config, remove the
   CLIENT's phone-home (hbb_common version_check_request), UI).
2. Configure client to use our local server (key `rKb+EardRcZ3Ugu3+76zh+vqvwMj67z8O+zNnKi8TtM=`).
3. Prove end-to-end connect + control between two instances.
4. Record final verified build commands into `tech-stack.md`.



### âœ… Done
- Defined project goal and feature parity list with UltraViewer (`project-overview.md`).
- Researched open-source bases; **chose RustDesk** and recorded the comparison
  and licensing caveats (`tech-stack.md`).
- Designed system architecture, module breakdown, and milestone roadmap
  (`architecture.md`).
- Created steering files as shared project memory.
- **Resolved all three open questions (decisions below).**

### âœ… Decisions locked
1. **Licensing: open-source.** RustDesk (AGPL-3.0) confirmed as the base; AGPL is
   fine because our product is open-source too.
2. **Infrastructure:** dev = local Docker; production = self-hosted single-node
   Kubernetes cluster.
3. **Product name:** JustKeepRemote (working name, may change).

### â­ï¸ Next (M0 â€” Foundations)
1. Install the Windows toolchain from `tech-stack.md` (Rust, VS Build Tools,
   Flutter, vcpkg, LLVM, CMake/Ninja, Docker).
2. Clone RustDesk client + rustdesk-server into the repo (as a studied base).
3. Stand up hbbs/hbbr locally via Docker; verify it runs.
4. Build the RustDesk client from source on this machine.
5. Prove an end-to-end connection between two instances using our local server.
6. Record exact, verified build/run commands back into `tech-stack.md`.

### Notes
- No application code written yet; repo currently contains only steering + .git.
