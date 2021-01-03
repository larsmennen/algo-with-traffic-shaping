#!/bin/bash
set -Eeuo pipefail functrace

#
# Run this as sudo
# This will add traffic shaping to the eth0 interface for all domains.
# Running this directly is for development purposes.
# In production, set up the cronjob using ./add-cronjob.sh
#

failure() {
  local lineno=$1
  local msg=$2
  echo "Failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

INTERFACE="eth0"
CURRENT_DIR="$(dirname "${0}")"
FILENAME="${CURRENT_DIR}/domains.txt"
# Config, change these to change the delays
MEAN_DELAY_MS=15000
STDDEV_DELAY_MS=5000

isipv6 () {
	if ! echo "$1" | grep -E '(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))' > /dev/null; then
		return 1
	fi
	return 0
}

echo "Deleting any existing traffic shaping on $INTERFACE"
if [ -n "$(tc qdisc show dev $INTERFACE | grep priomap)" ]
then
    echo "Removing existing traffic shaping on $INTERFACE"
    tc qdisc del dev $INTERFACE root
else
    echo "No traffic shaping on $INTERFACE detected"
fi

echo "Adding traffic shaping on $INTERFACE"
tc qdisc add dev $INTERFACE root handle 1: prio
tc qdisc add dev $INTERFACE parent 1:3 handle 30: netem delay ${MEAN_DELAY_MS}ms ${STDDEV_DELAY_MS}ms distribution normal

echo "Fetching domains"
current_prio=1
while read -r line; do
  echo "Domain: $line"
  all_ips=$((getent ahosts "$line" | grep " RAW" | awk '{ print $1 }') || true)
  if [ "$all_ips" = true ] || [ -z "$all_ips" ]; then
    echo "No IPs found, skipping."
    continue
  fi
  echo "Found $(echo -n "$all_ips" | grep -c '^') IPs"
  while IFS= read -r ip; do
    if ! isipv6 "$ip"; then
      echo "$ip is ipv4"
      tc filter add dev $INTERFACE protocol ip parent 1:0 prio $current_prio u32 match ip dst $ip/32 flowid 1:3
    else
      echo "$ip is ipv6"
      tc filter add dev $INTERFACE protocol ipv6 parent 1:0 prio $current_prio u32 match ip6 dst $ip flowid 1:3
    fi
    current_prio=$((current_prio+1))
  done <<< "$all_ips"
done < $FILENAME

echo "Added $((current_prio-1)) rules. Done!"
