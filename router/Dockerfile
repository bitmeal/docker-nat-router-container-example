FROM ubuntu:latest

# RUN apk add iptables dnsmasq
RUN apt update && apt install -y iproute2 iptables dnsmasq jq netmask bsdmainutils conntrack && rm /etc/dnsmasq.conf
#iputils-ping netcat dnsutils

COPY ./run.sh /run.sh
RUN chmod +x /run.sh && mkdir /data

ENTRYPOINT ["/run.sh"]
