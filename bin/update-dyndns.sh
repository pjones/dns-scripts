#!/bin/sh

################################################################################
set -e
set -u

################################################################################
export PATH=@extra_path@:$PATH

################################################################################
cache=/tmp/dyndns-ip-cache
url="https://cp.dnsmadeeasy.com/servlet/updateip?"
domain_id=""
domain_pass=""
username=""
ip=""

################################################################################
usage() {
cat <<EOF
Usage: update-dyndns.sh [options]

  -d ID   Set domain ID
  -h      This message
  -i ADDR Force DNS to use address ADDR
  -p PASS Set domain password
  -u NAME Set domain user name
EOF
}

################################################################################
while getopts "hd:p:u:i:" o; do
  case "${o}" in
    d) domain_id="$OPTARG"
       ;;

    h) usage
       exit
       ;;

    i) ip="$OPTARG"
       ;;

    p) domain_pass="$OPTARG"
       ;;

    u) username="$OPTARG"
       ;;

    *) exit 1
       ;;
  esac
done

shift $((OPTIND-1))

################################################################################
set -x

################################################################################
if [ -z "$ip" ]; then
  ip=$(ip route get 1 | awk '{print $7;exit}')
  #router=$(netstat -nr|awk '/^0.0.0.0/ {print $2}')
  #ip=$(snmpwalk -Os -c public -v 1 "$router" ipAdEntAddr|grep -v -F 127.0.0.1|grep -v -F "$router" | cut -d' ' -f4)
fi

################################################################################
if [ -r "$cache" ]; then
  current_ip=$(cat "$cache")
else
  current_ip=""
fi

################################################################################
if [ "$current_ip" != "$ip" ]; then
  url="${url}username=${username}&password=${domain_pass}&"
  url="${url}id=${domain_id}&ip=${ip}"

  if curl -s "$url" | grep -q success; then
    echo "$ip" > "$cache"
  else
    echo "Failed to update dynamic IP address!"
    exit 1
  fi
else
  echo "IP address hasn't changed (matches cache)"
fi
