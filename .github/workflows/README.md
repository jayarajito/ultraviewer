# CI/CD for the JustKeepRemote server

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | push / PR to development | Helm lint + render + guard rails, hadolint, SG-script tests, shellcheck, actionlint. No credentials. |
| `deploy-int.yml` | push to development (server/chart/script paths) or manual | Build image from source, smoke-test it, push to ECR, deploy to `jkr-int`. |
| `deploy-prod.yml` | manual only | Promote an existing int-built tag to `jkr-prod`. No rebuild. |

A push to `development` triggers `deploy-int` automatically (after you configure the items below).
Prod never deploys on its own.

## One-time setup (not done by the workflows)

**ECR repository** `jkr-server` in `us-east-1` (tags IMMUTABLE, scan on push):

```
aws ecr create-repository --repository-name jkr-server --region us-east-1 \
  --image-tag-mutability IMMUTABLE --image-scanning-configuration scanOnPush=true
```

**GitHub Environments** `int` and `production` (add required reviewers on `production`).

| Kind | Name | Value |
|---|---|---|
| secret | `KUBECONFIG_B64` | base64 of the kubeconfig |
| secret | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | credentials that can push/read ECR and edit the SG |
| variable | `ECR_REPOSITORY` | `<account>.dkr.ecr.us-east-1.amazonaws.com/jkr-server` (must end in `/jkr-server`) |
| variable | `AWS_REGION` | region of the security group |
| variable | `K8S_SECURITY_GROUP_ID` | node security group |
| variable | `RELAY_HOST` | public DNS name or IPv4 clients use for the relay. Set per environment. |

**Security group for clients** (your decision; the workflows do not touch it):
- prod: TCP 21115-21119 and UDP 21116
- int (optional): TCP 22115-22119 and UDP 22116

**DNS** for `RELAY_HOST` must resolve to the node's public address.

## Design notes

- **Two jobs in `deploy-int`.** The Rust compile takes 15-20 minutes. It runs in `build`, so the
  security-group rule is only opened in `deploy`, and the deploy timeout is not consumed.
- **Pinned upstream.** `rustdesk-server` is checked out at a full commit SHA
  (`UPSTREAM_REF` in the workflow `env`), and the build fails if the privacy patch anchor
  (removal of the hbbs phone-home to api.rustdesk.com) is not found.
- **Tested bytes are pushed bytes.** The image is built into the local daemon, smoke-tested as
  Kubernetes runs it (non-root, read-only rootfs, caps dropped), then tagged and pushed.
- **Immutable tags.** If the 12-character SHA tag already exists in ECR, build and push are skipped.
- **Cluster access.** The runner IP is added to the node SG for TCP 6443, a GitHub issue approval
  gates the deploy, and the rule is always removed (`if: always()`).
  The original `whitelist-runner-ip-and-rm.py` was not available, so `scripts/whitelist-public-ip/`
  holds a drop-in replacement with the same environment interface. It tags its rules
  `gha-jkr:<run>.<attempt>:<epoch>`, removes only its own rule, and sweeps its own rules older than 3 hours.
- **Recreate outage.** Host ports and a single volume force `Recreate`. Relayed sessions drop for
  under a minute per deploy. The prod approval issue says so.

## First install: back up the key

After the first deploy, read the private key once and store it in a password manager.
Never commit it. See `helm/jkr-server/README.md`.
