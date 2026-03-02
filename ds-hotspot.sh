#!/bin/bash

WLAN_INTERNET="wlp4s0"
WLAN_AP="wlx74da386bb09e"
DS_SUBNET="192.168.50.0/24"
LAN_SUBNET="10.0.0.0/24"
DS_IP="192.168.50.1"


# Path to hostapd config
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"

# Auto-detect AP interface: first wireless interface not equal to $WLAN_INTERNET
detect_ap() {
    # WLAN_AP=$(ip -o link show | awk -F': ' '/wl/{print $2}' | grep -v "$WLAN_INTERNET" | head -n1)
    # if [[ -z "$WLAN_AP" ]]; then
    #     echo "[-] No suitable wireless interface found for AP"
    #     exit 1
    # fi
    echo "[+] Detected AP interface: $WLAN_AP"
}

update_hostapd_conf() {
    if [[ ! -f "$HOSTAPD_CONF" ]]; then
        echo "[-] hostapd.conf not found at $HOSTAPD_CONF"
        exit 1
    fi

    echo "[+] Updating hostapd.conf to use interface $WLAN_AP"
    # Replace or add the interface line
    if grep -q "^interface=" "$HOSTAPD_CONF"; then
        sed -i "s|^interface=.*|interface=$WLAN_AP|" "$HOSTAPD_CONF"
    else
        echo "interface=$WLAN_AP" >> "$HOSTAPD_CONF"
    fi
}

create_chains() {
    iptables -N DS_FORWARD
    iptables -N DS_INPUT
}

delete_chains() {
   iptables -F DS_FORWARD 2>/dev/null
   iptables -X DS_FORWARD 2>/dev/null

   iptables -F DS_INPUT 2>/dev/null
   iptables -X DS_INPUT 2>/dev/null
}

#hook_chains() {
#    iptables -C FORWARD -i $WLAN_AP -j DS_FORWARD 2>/dev/null || \
#        iptables -I FORWARD 1 -i $WLAN_AP -j DS_FORWARD

#    iptables -C INPUT -i $WLAN_AP -j DS_INPUT 2>/dev/null || \
#        iptables -I INPUT 1 -i $WLAN_AP -j DS_INPUT
#}

unhook_chains() {
   iptables -D FORWARD -i $WLAN_AP -j DS_FORWARD 2>/dev/null
   iptables -D INPUT -i $WLAN_AP -j DS_INPUT 2>/dev/null
}

configure_firewall() {
    # Flush and remove old chains
    delete_chains

    # Create chains
    create_chains

    # DS -> Internet
    iptables -I FORWARD 1 -i $WLAN_AP -o $WLAN_INTERNET \
        -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

    # Internet -> DS (replies)
    iptables -I FORWARD 1 -i $WLAN_INTERNET -o $WLAN_AP \
        -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Block DS -> LAN
    iptables -I FORWARD 1 -i $WLAN_AP -d $LAN_SUBNET -j DROP

    # INPUT rules (traffic to the AP)
    iptables -C INPUT -i $WLAN_AP -j DS_INPUT 2>/dev/null || \
        iptables -I INPUT 1 -i $WLAN_AP -j DS_INPUT

    # DHCP (client -> server is 67/68)
    iptables -A DS_INPUT -p udp --dport 67:68 -j ACCEPT

    # DNS
    iptables -A DS_INPUT -p udp --dport 53 -j ACCEPT

    # Established
    iptables -A DS_INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Drop anything else from AP side
    iptables -A DS_INPUT -j DROP

    # NAT
    iptables -t nat -D POSTROUTING -s $DS_SUBNET -o $WLAN_INTERNET \
        -j MASQUERADE 2>/dev/null

    iptables -t nat -A POSTROUTING -s $DS_SUBNET -o $WLAN_INTERNET \
        -j MASQUERADE
}

remove_nat() {
    iptables -t nat -D POSTROUTING -s $DS_SUBNET -o $WLAN_INTERNET -j MASQUERADE 2>/dev/null
    iptables -t nat -F POSTROUTING
}

start_hotspot() {

    #detect_ap
    update_hostapd_conf

    echo "[+] Enabling IP forwarding"
    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    echo "[+] Setting AP interface $WLAN_AP unmanaged"
    nmcli dev set $WLAN_AP managed no 2>/dev/null

    echo "[+] Configuring AP interface"
    ip addr flush dev $WLAN_AP
    ip addr add $DS_IP/24 dev $WLAN_AP
    ip link set $WLAN_AP up

    echo "[+] Creating firewall chains"
    #create_chains
    #hook_chains
    configure_firewall

    echo "[+] Starting dnsmasq"
    systemctl restart dnsmasq

    echo "[+] Starting hostapd"
    systemctl restart hostapd

    echo "[+] DS Hotspot started (isolated mode)"
}

stop_hotspot() {
    #detect_ap

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