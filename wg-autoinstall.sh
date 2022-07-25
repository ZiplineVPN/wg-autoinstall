#!/bin/bash

SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
SERVER_PUB_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
SERVER_WG_NIC="wg0"
SERVER_WG_IPV4="10.66.66.1"
SERVER_WG_IPV6="fd42:42:42::1"
SERVER_PORT=$(shuf -i49152-65535 -n1)
ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"
CLIENT_DNS_1="8.8.8.8"
CLIENT_DNS_2="8.8.4.4"
HOME_DIR="/root"


function newClient() {
	
	#for DOT_IP in {2..254}; do
	#	DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf")
	#	if [[ ${DOT_EXISTS} == '0' ]]; then
	#		break
	#	fi
	#done
	CLIENT_NAME=$1
	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
	BASE_IP=$(echo "$SERVER_WG_IPV6" | awk -F '::' '{ print $1 }')
	CLIENT_WG_IPV6="${BASE_IP}::${DOT_IP}"
	
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)

	# Create client file and add the server as a peer
	echo "[Interface]
	PrivateKey = ${CLIENT_PRIV_KEY}
	Address = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128
	DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

	[Peer]
	PublicKey = ${SERVER_PUB_KEY}
	PresharedKey = ${CLIENT_PRE_SHARED_KEY}
	Endpoint = ${ENDPOINT}
	AllowedIPs = 0.0.0.0/0,::/0" >>"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	# Add the client as a peer to the server
	echo -e "\n### Client ${CLIENT_NAME}
	[Peer]
	PublicKey = ${CLIENT_PUB_KEY}
	PresharedKey = ${CLIENT_PRE_SHARED_KEY}
	AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")

	qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	echo "${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
}


if [[ -e /etc/wireguard/params ]]; then
	echo "Wireguard Installed."
else
	apt-get update
	apt-get install -y wireguard iptables resolvconf qrencode

	mkdir /etc/wireguard >/dev/null 2>&1

	chmod 600 -R /etc/wireguard/

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

	# Save WireGuard settings
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}
	SERVER_PUB_NIC=${SERVER_PUB_NIC}
	SERVER_WG_NIC=${SERVER_WG_NIC}
	SERVER_WG_IPV4=${SERVER_WG_IPV4}
	SERVER_WG_IPV6=${SERVER_WG_IPV6}
	SERVER_PORT=${SERVER_PORT}
	SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
	SERVER_PUB_KEY=${SERVER_PUB_KEY}
	CLIENT_DNS_1=${CLIENT_DNS_1}
	CLIENT_DNS_2=${CLIENT_DNS_2}" >/etc/wireguard/params

	echo "[Interface]
	Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
	ListenPort = ${SERVER_PORT}
	PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${SERVER_WG_NIC}.conf"

	if pgrep firewalld; then
		FIREWALLD_IPV4_ADDRESS=$(echo "${SERVER_WG_IPV4}" | cut -d"." -f1-3)".0"
		FIREWALLD_IPV6_ADDRESS=$(echo "${SERVER_WG_IPV6}" | sed 's/:[^:]*$/:0/')
		echo "PostUp = firewall-cmd --add-port ${SERVER_PORT}/udp && firewall-cmd --add-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade' && firewall-cmd --add-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS}/24 masquerade'
		PostDown = firewall-cmd --remove-port ${SERVER_PORT}/udp && firewall-cmd --remove-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade' && firewall-cmd --remove-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS}/24 masquerade'" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	else
		echo "PostUp = iptables -A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT; iptables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE; ip6tables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
		PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT; iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE; ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	fi

	echo "net.ipv4.ip_forward = 1
	net.ipv6.conf.all.forwarding = 1" >/etc/sysctl.d/wg.conf
	sysctl --system
	systemctl start "wg-quick@${SERVER_WG_NIC}"
	systemctl enable "wg-quick@${SERVER_WG_NIC}"

	newClient "default"

	systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
	WG_RUNNING=$?

	if [[ ${WG_RUNNING} -ne 0 ]]; then
		echo -e "\n${RED}WARNING: WireGuard does not seem to be running.${NC}"
		echo -e "${ORANGE}You can check if WireGuard is running with: systemctl status wg-quick@${SERVER_WG_NIC}${NC}"
		echo -e "${ORANGE}If you get something like \"Cannot find device ${SERVER_WG_NIC}\", please reboot!${NC}"
	fi
fi
