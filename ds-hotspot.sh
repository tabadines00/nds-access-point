#!/bin/bash

WLAN_INTERNET="wlp4s0"
WLAN_AP="wlx74da386bb09e"
DS_SUBNET="192.168.50.0/24"
LAN_SUBNET="192.168.1.0/24"
DS_IP="192.168.50.1"

create_chains() {
    iptables -N DS_FORWARD 2>/dev/null
    iptables -N DS_INPUT 2>/dev/null
}

delete_chains() {
    iptables -F DS_FORWARD 2>/dev/null
    iptables -X DS_FORWARD 2>/dev/null

    iptables -F DS_INPUT 2>/dev/null
    iptables -X DS_INPUT 2>/dev/null
}

hook_chains() {
    iptables -C FORWARD -i $WLAN_AP -j DS_FORWARD 2>/dev/null || \
        iptables -I FORWARD 1 -i $WLAN_AP -j DS_FORWARD

    iptables -C INPUT -i $WLAN_AP -j DS_INPUT 2>/dev/null || \
        iptables -I INPUT 1 -i $WLAN_AP -j DS_INPUT
}

unhook_chains() {
    iptables -D FORWARD -i $WLAN_AP -j DS_FORWARD 2>/dev/null
    iptables -D INPUT -i $WLAN_AP -j DS_INPUT 2>/dev/null
}

configure_firewall() {
    iptables -F DS_FORWARD
    iptables -F DS_INPUT

    # Allow DS → Internet
    iptables -A DS_FORWARD -o $WLAN_INTERNET -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

    # Allow return traffic
    iptables -A DS_FORWARD -i $WLAN_INTERNET -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Block DS → LAN
    iptables -A DS_FORWARD -d $LAN_SUBNET -j DROP

    # Default drop
    iptables -A DS_FORWARD -j DROP

    # Block DS → host completely
    iptables -A DS_INPUT -j DROP

    # NAT (subnet scoped, idempotent)
    iptables -t nat -C POSTROUTING -s $DS_SUBNET -o $WLAN_INTERNET -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -s $DS_SUBNET -o $WLAN_INTERNET -j MASQUERADE
}

remove_nat() {
    iptables -t nat -D POSTROUTING -s $DS_SUBNET -o $WLAN_INTERNET -j MASQUERADE 2>/dev/null
}

start_hotspot() {
    echo "[+] Enabling IP forwarding"
    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    echo "[+] Configuring AP interface"
    ip addr flush dev $WLAN_AP
    ip addr add $DS_IP/24 dev $WLAN_AP
    ip link set $WLAN_AP up

    echo "[+] Creating firewall chains"
    create_chains
    hook_chains
    configure_firewall

    echo "[+] Starting dnsmasq"
    systemctl restart dnsmasq

    echo "[+] Starting hostapd"
    systemctl restart hostapd

    echo "[+] DS Hotspot started (isolated mode)"
}

stop_hotspot() {
    echo "[-] Stopping hostapd"
    systemctl stop hostapd

    echo "[-] Stopping dnsmasq"
    systemctl stop dnsmasq

    echo "[-] Removing NAT rule"
    remove_nat

    echo "[-] Unhooking firewall chains"
    unhook_chains

    echo "[-] Deleting firewall chains"
    delete_chains

    echo "[-] Disabling IP forwarding"
    sysctl -w net.ipv4.ip_forward=0 > /dev/null

    echo "[-] DS Hotspot stopped cleanly"
}

case "$1" in
    start)
        start_hotspot
        ;;
    stop)
        stop_hotspot
        ;;
    restart)
        stop_hotspot
        start_hotspot
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
