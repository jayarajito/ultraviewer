"""Unit tests for whitelist-runner-ip-and-rm.py using a fake EC2 client (no AWS, no boto3).

Run:  python -m unittest discover -s scripts/whitelist-public-ip -v
"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "wl", pathlib.Path(__file__).with_name("whitelist-runner-ip-and-rm.py")
)
wl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wl)

SG = "sg-0123456789abcdef0"
NOW = 1_800_000_000


class FakeClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeEC2:
    """Just enough of the EC2 API. Rules are (port, cidr, description) tuples."""

    def __init__(self, rules=()):
        self.rules = list(rules)
        self.calls = []

    def describe_security_groups(self, GroupIds):
        perms = [
            {
                "IpProtocol": "tcp",
                "FromPort": port,
                "ToPort": port,
                "IpRanges": [{"CidrIp": cidr, "Description": desc}],
            }
            for port, cidr, desc in self.rules
        ]
        return {"SecurityGroups": [{"GroupId": GroupIds[0], "IpPermissions": perms}]}

    def authorize_security_group_ingress(self, GroupId, IpPermissions):
        self.calls.append(("authorize", IpPermissions))
        rng = IpPermissions[0]["IpRanges"][0]
        port = IpPermissions[0]["FromPort"]
        if any(p == port and c == rng["CidrIp"] for p, c, _ in self.rules):
            raise FakeClientError("InvalidPermission.Duplicate")
        self.rules.append((port, rng["CidrIp"], rng.get("Description", "")))

    def revoke_security_group_ingress(self, GroupId, IpPermissions):
        self.calls.append(("revoke", IpPermissions))
        rng = IpPermissions[0]["IpRanges"][0]
        port = IpPermissions[0]["FromPort"]
        self.rules = [r for r in self.rules if not (r[0] == port and r[1] == rng["CidrIp"])]


def cfg(ip="8.8.4.4", **kw):
    # NB: documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) are NOT
    # "global" per Python's ipaddress, so tests use a real public address instead.
    base = {
        "ip": wl.validate_public_ipv4(ip),
        "sg": SG,
        "region": "us-east-1",
        "port": 6443,
        "cleanup": False,
        "run_tag": "gha-jkr:111.1:",
    }
    base.update(kw)
    return base


class ValidateIp(unittest.TestCase):
    def test_accepts_public_ipv4(self):
        self.assertEqual(wl.validate_public_ipv4(" 8.8.8.8 "), "8.8.8.8")

    def test_rejects_unsafe_values(self):
        for bad in ["", "abc", "10.0.0.5", "192.168.1.1", "172.16.0.1", "127.0.0.1",
                    "169.254.1.1", "0.0.0.0", "224.0.0.1", "255.255.255.255",
                    "8.8.8.8/0", "0.0.0.0/0", "2001:4860:4860::8888", "8.8.8.8, 1.1.1.1"]:
            with self.subTest(bad=bad), self.assertRaises(wl.UsageError):
                wl.validate_public_ipv4(bad)


class ReadConfig(unittest.TestCase):
    ENV = {"RUNNER_PUBLIC_IPV4": "8.8.8.8", "SECURITY_GROUP_ID": SG, "AWS_REGION": "us-east-1",
           "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "2"}

    def test_defaults_and_tag(self):
        c = wl.read_config(self.ENV)
        self.assertEqual((c["port"], c["cleanup"], c["run_tag"]), (6443, False, "gha-jkr:42.2:"))

    def test_cleanup_flag_is_strict(self):
        self.assertTrue(wl.read_config({**self.ENV, "CLEANUP": "true"})["cleanup"])
        self.assertTrue(wl.read_config({**self.ENV, "CLEANUP": "TRUE"})["cleanup"])
        self.assertFalse(wl.read_config({**self.ENV, "CLEANUP": "1"})["cleanup"])

    def test_missing_and_bad_values(self):
        for drop in ("RUNNER_PUBLIC_IPV4", "SECURITY_GROUP_ID", "AWS_REGION"):
            env = {k: v for k, v in self.ENV.items() if k != drop}
            with self.subTest(drop=drop), self.assertRaises(wl.UsageError):
                wl.read_config(env)
        for bad_port in ("0", "70000", "abc", "-1"):
            with self.subTest(port=bad_port), self.assertRaises(wl.UsageError):
                wl.read_config({**self.ENV, "K8S_API_PORT": bad_port})


class AddRemove(unittest.TestCase):
    def test_add_creates_one_tagged_slash32_rule(self):
        ec2 = FakeEC2()
        self.assertEqual(wl.add_rule(ec2, cfg(), now=NOW), "added")
        self.assertEqual(ec2.rules, [(6443, "8.8.4.4/32", f"gha-jkr:111.1:{NOW}")])

    def test_remove_removes_only_this_runs_rule(self):
        ec2 = FakeEC2()
        wl.add_rule(ec2, cfg(), now=NOW)
        self.assertEqual(wl.remove_rule(ec2, cfg(cleanup=True)), "removed")
        self.assertEqual(ec2.rules, [])

    def test_never_claims_or_removes_a_preexisting_rule_for_same_ip(self):
        theirs = (6443, "8.8.4.4/32", "lotto-deploy")
        ec2 = FakeEC2([theirs])
        self.assertEqual(wl.add_rule(ec2, cfg(), now=NOW), "preexisting")
        self.assertEqual(wl.remove_rule(ec2, cfg(cleanup=True)), "absent")
        self.assertEqual(ec2.rules, [theirs])  # untouched

    def test_does_not_remove_another_runs_tagged_rule(self):
        other = (6443, "8.8.4.4/32", f"gha-jkr:999.1:{NOW}")
        ec2 = FakeEC2([other])
        self.assertEqual(wl.remove_rule(ec2, cfg(cleanup=True)), "absent")
        self.assertEqual(ec2.rules, [other])

    def test_remove_with_nothing_to_remove_is_a_noop(self):
        self.assertEqual(wl.remove_rule(FakeEC2(), cfg(cleanup=True)), "absent")

    def test_other_ports_are_ignored(self):
        other_port = (22, "8.8.4.4/32", "gha-jkr:111.1:1")
        ec2 = FakeEC2([other_port])
        self.assertEqual(wl.remove_rule(ec2, cfg(cleanup=True)), "absent")
        self.assertEqual(ec2.rules, [other_port])

    def test_unexpected_aws_error_propagates(self):
        class Boom(FakeEC2):
            def authorize_security_group_ingress(self, **kw):
                raise FakeClientError("UnauthorizedOperation")

        with self.assertRaises(FakeClientError):
            wl.add_rule(Boom(), cfg(), now=NOW)


class Sweep(unittest.TestCase):
    def test_sweeps_only_old_rules_with_our_prefix(self):
        old = NOW - wl.STALE_AFTER_SECONDS - 10
        fresh = NOW - 60
        rules = [
            (6443, "1.1.1.1/32", f"gha-jkr:1.1:{old}"),      # ours, stale  -> swept
            (6443, "1.1.1.2/32", f"gha-jkr:2.1:{fresh}"),    # ours, fresh  -> kept
            (6443, "1.1.1.3/32", "lotto-deploy"),            # not ours     -> kept
            (6443, "1.1.1.4/32", f"other-tool:{old}"),       # not ours     -> kept
            (6443, "1.1.1.5/32", "gha-jkr:3.1:notanumber"),  # malformed    -> kept
            (6443, "1.1.1.6/32", ""),                        # no desc      -> kept
        ]
        ec2 = FakeEC2(rules)
        self.assertEqual(wl.sweep_stale(ec2, SG, 6443, now=NOW), 1)
        self.assertEqual([r[1] for r in ec2.rules],
                         ["1.1.1.2/32", "1.1.1.3/32", "1.1.1.4/32", "1.1.1.5/32", "1.1.1.6/32"])


if __name__ == "__main__":
    unittest.main()
