#!/bin/bash

if [[ -e /etc/wireguard/params ]]; then
  echo "true"
else
	echo "false"
fi
