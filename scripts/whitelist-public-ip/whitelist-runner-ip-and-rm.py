#!/usr/bin/env python3
"""Temporarily allow a GitHub-hosted runner to reach the Kubernetes API, then remove it.

Drop-in for the script your other workflows call (same path, same environment
variables). Adds ONE inbound rule on the cluster's EC2 security group:

    tcp / K8S_API_PORT (default 6443) / <runner ip>/32

and, when CLEANUP=true, removes exactly that rule again.

Environment
-----------
RUNNER_PUBLIC_IPV4  required  public IPv4 of the runner (from api.ipify.org)
SECURITY_GROUP_ID   required  e.g. sg-0123456789abcdef0
AWS_REGION          required  region of the security group
CLEANUP             optional  "true" -> remove the rule this run added; anything else -> add
K8S_API_PORT        optional  default 6443
GITHUB_RUN_ID / GITHUB_RUN_ATTEMPT  set by GitHub; make the rule description unique

AWS credentials come from the standard environment (aws-actions/configure-aws-credentials).
Needs: ec2:DescribeSecurityGroups, ec2:AuthorizeSecurityGroupIngress,
ec2:RevokeSecurityGroupIngress on that group.

Safety properties (this guards the cluster API, so they matter)
----------------------------------------------------------------
* Only a single public unicast IPv4 is ever accepted, always as /32. Private, loopback,
  link-local, multicast, reserved and 0.0.0.0 are rejected; there is no way to open a range.
* Every rule is tagged in its description as  gha-jkr:<run>.<attempt>:<epoch>.
  Cleanup revokes ONLY a rule carrying THIS run's tag. A rule for the same IP that already
  existed (another app's workflow, or a permanent rule) is never claimed, so it is never
  removed. Rules that don't start with "gha-jkr:" are never touched at all.
* Stale rules from earlier runs of THIS tooling (crashed runner, cancelled before cleanup)
  are swept on the next add once they are older than STALE_AFTER_SECONDS.
* Cleanup that finds nothing to remove is a no-op (exit 0). A cleanup that FAILS exits
  non-zero and prints a ::error:: so a rule left open is impossible to miss.
"""
from __future__ import annotations

import ipaddress
import os
import sys
import time

PREFIX = "gha-jkr"
STALE_AFTER_SECONDS = 3 * 60 * 60  # 3 h; a deploy job times out at 30-60 min


class UsageError(Exception):
    """Bad input/environment. Exit code 2."""


def validate_public_ipv4(value: str) -> str:
    """Return the canonical text of a public unicast IPv4, or raise UsageError."""
    try:
        ip = ipaddress.ip_address((value or "").strip())
    except ValueError as exc:
        raise UsageError(f"RUNNER_PUBLIC_IPV4 is not an IP address: {value!r}") from exc
    if ip.version != 4:
        raise UsageError(f"only IPv4 is supported, got {ip}")
    if not ip.is_global or ip.is_multicast:
        raise UsageError(f"refusing non-public address {ip} (private/loopback/link-local/reserved)")
    return str(ip)


def read_config(env: "dict[str, str] | os._Environ[str]" = os.environ) -> dict:
    def need(name: str) -> str:
        v = (env.get(name) or "").strip()
        if not v:
            raise UsageError(f"{name} is required")
        return v

    port_text = (env.get("K8S_API_PORT") or "6443").strip()
    if not port_text.isdigit() or not (1 <= int(port_text) <= 65535):
        raise UsageError(f"K8S_API_PORT must be 1-65535, got {port_text!r}")
    run_id = (env.get("GITHUB_RUN_ID") or "local").strip()
    attempt = (env.get("GITHUB_RUN_ATTEMPT") or "1").strip()
    return {
        "ip": validate_public_ipv4(need("RUNNER_PUBLIC_IPV4")),
        "sg": need("SECURITY_GROUP_ID"),
        "region": need("AWS_REGION"),
        "port": int(port_text),
        "cleanup": (env.get("CLEANUP") or "").strip().lower() == "true",
        "run_tag": f"{PREFIX}:{run_id}.{attempt}:",
    }


def _rules_for_port(ec2, sg: str, port: int):
    """Yield (cidr, description) for every IPv4 tcp rule that covers exactly `port`."""
    resp = ec2.describe_security_groups(GroupIds=[sg])
    for group in resp.get("SecurityGroups", []):
        for perm in group.get("IpPermissions", []):
            if perm.get("IpProtocol") != "tcp":
                continue
            if perm.get("FromPort") != port or perm.get("ToPort") != port:
                continue
            for rng in perm.get("IpRanges", []):
                yield rng.get("CidrIp", ""), rng.get("Description", "") or ""


def _permission(port: int, cidr: str, description: str | None = None) -> list:
    rng = {"CidrIp": cidr}
    if description is not None:
        rng["Description"] = description
    return [{"IpProtocol": "tcp", "FromPort": port, "ToPort": port, "IpRanges": [rng]}]


def _error_code(exc: Exception) -> str:
    return getattr(exc, "response", {}).get("Error", {}).get("Code", "")


def sweep_stale(ec2, sg: str, port: int, now: float | None = None) -> int:
    """Revoke OUR OWN tagged rules older than STALE_AFTER_SECONDS. Returns how many."""
    now = time.time() if now is None else now
    removed = 0
    for cidr, desc in list(_rules_for_port(ec2, sg, port)):
        if not desc.startswith(PREFIX + ":"):
            continue  # not ours - never touch
        try:
            epoch = int(desc.rsplit(":", 1)[1])
        except (IndexError, ValueError):
            continue  # malformed tag - leave it, a human should look
        if now - epoch > STALE_AFTER_SECONDS:
            ec2.revoke_security_group_ingress(GroupId=sg, IpPermissions=_permission(port, cidr))
            print(f"swept stale rule {cidr} ({desc})")
            removed += 1
    return removed


def add_rule(ec2, cfg: dict, now: float | None = None) -> str:
    """Add the tagged /32 rule. Returns 'added' or 'preexisting'."""
    now = time.time() if now is None else now
    sweep_stale(ec2, cfg["sg"], cfg["port"], now)
    cidr = f"{cfg['ip']}/32"
    description = f"{cfg['run_tag']}{int(now)}"
    try:
        ec2.authorize_security_group_ingress(
            GroupId=cfg["sg"], IpPermissions=_permission(cfg["port"], cidr, description)
        )
    except Exception as exc:  # botocore.exceptions.ClientError
        if _error_code(exc) == "InvalidPermission.Duplicate":
            # Someone else already allows this IP on this port. Don't claim it, so cleanup
            # (which only removes rules tagged with THIS run) will leave it alone.
            print(f"{cidr} already allowed on tcp/{cfg['port']} by another rule; not touching it")
            return "preexisting"
        raise
    print(f"allowed {cidr} -> tcp/{cfg['port']} on {cfg['sg']} ({description})")
    return "added"


def remove_rule(ec2, cfg: dict) -> str:
    """Remove the rule THIS run added. Returns 'removed' or 'absent'."""
    cidr = f"{cfg['ip']}/32"
    for found_cidr, desc in _rules_for_port(ec2, cfg["sg"], cfg["port"]):
        if found_cidr == cidr and desc.startswith(cfg["run_tag"]):
            ec2.revoke_security_group_ingress(
                GroupId=cfg["sg"], IpPermissions=_permission(cfg["port"], cidr)
            )
            print(f"removed {cidr} from {cfg['sg']} tcp/{cfg['port']} ({desc})")
            return "removed"
    print(f"no rule tagged {cfg['run_tag']}* for {cidr} on tcp/{cfg['port']}; nothing to remove")
    return "absent"


def main() -> int:
    try:
        cfg = read_config()
    except UsageError as exc:
        print(f"::error::{exc}")
        return 2
    import boto3  # imported late so the helpers above can be unit-tested without boto3

    ec2 = boto3.client("ec2", region_name=cfg["region"])
    try:
        if cfg["cleanup"]:
            remove_rule(ec2, cfg)
        else:
            add_rule(ec2, cfg)
    except Exception as exc:  # noqa: BLE001 - report everything, never swallow
        action = "remove" if cfg["cleanup"] else "add"
        print(f"::error::could not {action} the security-group rule: {exc}")
        if cfg["cleanup"]:
            print(
                f"::error::THE TEMPORARY RULE FOR {cfg['ip']}/32 ON {cfg['sg']} MAY STILL BE OPEN - "
                "remove it manually in the EC2 console"
            )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
