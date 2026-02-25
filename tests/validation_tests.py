import subprocess
import sys

WLAN_AP = "wlx74da386bb09e"
DS_GATEWAY = "192.168.50.1"
TEST_IP = "192.168.50.100"
LAN_ROUTER = "192.168.1.1"
INTERNET_IP = "8.8.8.8"
NAMESPACE = "ds_test"

def run(cmd):
    return subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def check(condition, success_msg, fail_msg):
    if condition:
        print(f"[PASS] {success_msg}")
    else:
        print(f"[FAIL] {fail_msg}")

def setup_namespace():
    run(f"ip netns add {NAMESPACE}")
    run(f"ip link add veth0 type veth peer name veth1")
    run(f"ip link set veth1 netns {NAMESPACE}")

    run(f"ip addr add 192.168.50.254/24 dev veth0")
    run("ip link set veth0 up")

    run(f"ip netns exec {NAMESPACE} ip addr add {TEST_IP}/24 dev veth1")
    run(f"ip netns exec {NAMESPACE} ip link set veth1 up")
    run(f"ip netns exec {NAMESPACE} ip route add default via {DS_GATEWAY}")

def cleanup_namespace():
    run(f"ip netns delete {NAMESPACE}")
    run("ip link delete veth0")

def ping_from_ns(target):
    result = run(f"ip netns exec {NAMESPACE} ping -c 1 -W 1 {target}")
    return result.returncode == 0

def check_iptables_chain(chain):
    result = run(f"iptables -L {chain}")
    return result.returncode == 0

def check_nat_rule():
    result = run("iptables -t nat -C POSTROUTING -s 192.168.50.0/24 -j MASQUERADE")
    return result.returncode == 0

def main():
    print("Setting up test namespace...")
    setup_namespace()

    print("\nRunning network validation tests:\n")

    check(
        ping_from_ns(INTERNET_IP),
        "Internet reachable (NAT working)",
        "Internet NOT reachable"
    )

    check(
        not ping_from_ns(LAN_ROUTER),
        "LAN correctly blocked",
        "LAN is reachable — isolation FAILED"
    )

    check(
        not ping_from_ns(DS_GATEWAY),
        "Host correctly blocked",
        "Host is reachable — isolation FAILED"
    )

    check(
        check_iptables_chain("DS_FORWARD"),
        "DS_FORWARD chain exists",
        "DS_FORWARD chain missing"
    )

    check(
        check_nat_rule(),
        "Scoped NAT rule present",
        "Scoped NAT rule missing"
    )

    print("\nCleaning up...")
    cleanup_namespace()

if __name__ == "__main__":
    if sys.platform != "linux":
        print("This test suite must be run on Linux.")
        sys.exit(1)
    main()
