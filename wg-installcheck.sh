#!/bin/bash

if [[ -e /etc/wireguard/params && -e /root/wg0-client-default.conf ]]; then
	echo "true"
else
	echo "false"
fi
