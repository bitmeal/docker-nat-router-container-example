#!/bin/sh

if [ ! ${ROUTER_DNS} ]; then
    echo "ROUTER_DNS variable not set!"
    exit 1
fi

DNS_IP=$(getent hosts ${ROUTER_DNS} | awk '{ print $1 }')

echo "entering ${DNS_IP} as dns server in /etc/resolv.conf"
echo "nameserver ${DNS_IP}" > /etc/resolv.conf

echo "executing supplied command line: ${@}"
exec "${@}"
