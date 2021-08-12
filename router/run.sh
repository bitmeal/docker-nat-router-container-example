#!/bin/bash

# ENV:
#   - ROUTE_NET
#   - (ROUTE_GATEWAY)

if [ ! ${ROUTE_NET}]; then
    echo "no routed network specifed by ROUTE_NET; selecting from first interface"
    IF_INFO="$(ip -json a | jq -r '[.[] | select(.ifname!="lo")][0]')"
    IF_NAME="$(echo ${IF_INFO} | jq -r .ifname)"
    IF_ADDR_INFO="$(echo ${IF_INFO} | jq -r '[.addr_info | .[] | select(.family=="inet")][0]')"
    IF_ADDR="$(echo ${IF_ADDR_INFO} | jq -r .local)"
    IF_PREFIX="$(echo ${IF_ADDR_INFO} | jq -r .prefixlen)"
    ROUTE_NET=$(netmask ${IF_ADDR}/${IF_PREFIX} | grep -oP '\S*')
    echo "using ${ROUTE_NET} from ${IF_NAME}"
fi


ROUTE_NET_USER=${ROUTE_NET}
ROUTE_NET=$(netmask ${ROUTE_NET} | grep -oP '\S*')

echo "network to route from ${ROUTE_NET} (${ROUTE_NET_USER})"

for IFACE_ADDRS in $(ip -json a | jq -r '.[] as {$ifname, $addr_info} | $addr_info | map("\(.local)/\(.prefixlen);\($ifname)") | .[]'); do
    IFS=';' read -r -a IFACE_ADDRS <<< "${IFACE_ADDRS}"    
    NET="$(netmask ${IFACE_ADDRS[0]} | grep -oP '\S*')"

    if [ "${NET}" == "${ROUTE_NET}" ]; then
        ROUTE_ADDRESS="${IFACE_ADDRS[0]}"
        ROUTE_IF="${IFACE_ADDRS[1]}"
    fi
done

# break if interface not found
if [ ! ${ROUTE_IF} ]; then
    echo "could not get routing interface for net ${ROUTE_NET}"
    echo "known interfaces and addresses:"
    ip -json a | jq -r '.[] as {$ifname, $addr_info} | $addr_info | map("\($ifname) \(.local)/\(.prefixlen)") | .[]' | column -t -s' '

    exit 1
fi

# check for IPv4 forwarding
if [ $(cat /proc/sys/net/ipv4/ip_forward) != 1 ]; then
    echo "ipv4 forwarding is disabled!"
    exit 1
fi

# echo "removing ${ROUTE_ADDRESS} on interface ${ROUTE_IF}"
# ip addr del ${ROUTE_ADDRESS} dev ${ROUTE_IF}


if [ ! ${ROUTE_GATEWAY} ]; then
    # ROUTE_GATEWAY=$(echo ${ROUTE_NET} | sed -E 's#[[:digit:]]{1,3}/([[:digit:]]{1,3})#1/\1#')
    ROUTE_NET_LOWER=$(netmask -r ${ROUTE_NET} | sed -E 's/^\s*(.*)-.*/\1/')
    ROUTE_NET_BRC=$(echo ${ROUTE_NET_LOWER} | sed -E 's/([[:digit:]]{1,3}\.){3}//')
    ROUTE_NET_24=$(echo ${ROUTE_NET_LOWER} | grep -oP '([[:digit:]]{1,3}\.){3}')
    let ROUTE_NET_GW=ROUTE_NET_BRC+1
    ROUTE_GATEWAY="${ROUTE_NET_24}${ROUTE_NET_GW}"
fi

if [[ "${ROUTE_GATEWAY}" != *"/"* ]]; then
    ROUTE_NET_SUBNET=$(echo ${ROUTE_NET} | grep -oP '/\d+$')
    echo "adding subnet ${ROUTE_NET_SUBNET} to gateway address"
fi

echo "using gateway address ${ROUTE_GATEWAY}"

echo "writing resolv.conf for routed clients in /data/resolv.conf"
tac /etc/resolv.conf | sed "/^nameserver.*/i nameserver $(echo ${ROUTE_GATEWAY} | sed -E 's#/[[:digit:]]+$##')" | tac > /data/resolv.conf

echo "adding ${ROUTE_GATEWAY} on interface ${ROUTE_IF}"
ip addr add ${ROUTE_GATEWAY} dev ${ROUTE_IF}

for TARGET_IF in $(ip -json a | jq -r  --arg IFNAME "${ROUTE_IF}" '.[] | select(.ifname!=$IFNAME and .ifname!="lo") | .ifname'); do
    echo "enabling NAT and FORWARD from ${ROUTE_IF} to ${TARGET_IF}"
    
    # iptables -I FORWARD 1 -i ${TARGET_IF} -o ${ROUTE_IF} -j ACCEPT
    # iptables -I FORWARD 1 -i ${ROUTE_IF} -o ${TARGET_IF} -j ACCEPT

    iptables -A FORWARD -o ${TARGET_IF} -i ${ROUTE_IF} -s ${ROUTE_NET} -m conntrack --ctstate NEW -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    iptables -t nat -I POSTROUTING 1 -o ${TARGET_IF} -j MASQUERADE
done

echo "starting dnsmasq..."
dnsmasq -q -d &

if [ ${@} ]; then
    echo "executing supplied command line: ${@}"
    # exec "${@}"
    ${@}
else
    echo "monitoring NAT connections..."
    conntrack -E
fi