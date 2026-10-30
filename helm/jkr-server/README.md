# jkr-server Helm chart

Deploys the JustKeepRemote ID/rendezvous (`hbbs`) and relay (`hbbr`) server, built from
source by `server/Dockerfile`.

## Design decisions

- **One pod, two containers, exactly one replica.** The server needs fixed host ports and a
  ReadWriteOnce volume holding its keypair, so there is deliberately no `replicaCount`.
- **`hostNetwork: true`.** The cluster has no LoadBalancer, NodePort cannot serve fixed ports
  or UDP 21116, and hbbs needs the real client source address for LAN detection and hole
  punching. Consequences:
  - The node firewall / AWS security group must allow the derived ports.
  - The strategy is `Recreate`. A rollout stops the old pod before the new one starts, so
    relayed sessions drop for the duration of the restart.
  - A namespace enforcing the Pod Security `baseline` or `restricted` profile rejects
    hostNetwork pods. The `jkr-*` namespaces must not enforce those profiles.
- **Ports.** `ports.rendezvous` (hbbs, default 21116) and `ports.relay` (hbbr, default 21117).
  hbbs also uses `rendezvous-1` (NAT test) and `rendezvous+2` (websocket). hbbr also uses
  `relay+2` (websocket). The render fails if any two collide.
  - prod: 21115-21119 (standard RustDesk ports, so clients need no `:port` suffix)
  - int: 22115-22119, so int and prod can share one node.
- **`relayHost` is required.** It is what hbbs hands to clients as the relay address, so it must
  be a public name or IP reachable by clients. hbbs silently drops a relay host it cannot
  resolve (leaving `relay-servers=[]` and the symptom "Failed to connect to relay server"), so
  the start script exits with `FATAL: RELAY_HOST ... does not resolve` and the deploy smoke
  test checks the hbbs log for the expected `relay-servers=[...]` line.
- **Storage.** PVC `storageClassName` is immutable on an existing claim. Prod uses
  `ebs-gp3-database` (Retain) and the PVC carries `helm.sh/resource-policy: keep`, so
  `helm uninstall` or a rolled-back first install cannot delete the keypair. Int uses `ebs-gp3`
  and is disposable.
- **Hardening.** Non-root (uid 10001), read-only root filesystem, all capabilities dropped,
  `-k _` on both servers (clients must present the server's key).

## Install (done by the workflows, shown for reference)

```
helm upgrade --install jkr-server helm/jkr-server \
  --namespace jkr-int --values helm/jkr-server/values-int.yaml \
  --set image.repository=<account>.dkr.ecr.<region>.amazonaws.com/jkr-server \
  --set image.tag=<12-char-git-sha> \
  --set-string relayHost=relay.example.com
```

## Server key: back it up once

Every client pins the server's public key. If the volume is lost the keypair is regenerated
and every client is rejected until reconfigured.

```
kubectl -n jkr-prod exec deploy/jkr-server -c hbbs -- cat /data/id_ed25519.pub   # public, goes in clients
kubectl -n jkr-prod exec deploy/jkr-server -c hbbs -- cat /data/id_ed25519       # PRIVATE: store in a password manager
```

Never commit the private key. The deploy workflows fail if the public key changes between the
start and the end of a deploy.

## Local verification

`bash scripts/helm-verify.sh` (Windows: `scripts\helm-verify.ps1`) runs `helm lint --strict`,
renders int and prod, exercises the guard rails (missing values, bad host names, port
collisions), checks the int/prod port sets are disjoint, and validates against the
Kubernetes 1.30 schemas with kubeconform. CI runs the same script.
