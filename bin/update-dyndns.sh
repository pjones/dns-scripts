#!/usr/bin/env bash

################################################################################
set -eu
set -o pipefail

################################################################################
export PATH=@extra_path@:$PATH

################################################################################
cache_file=/tmp/dyndns-ip-cache
base_url="https://api.dnsmadeeasy.com/V2.0"
option_api_key_file=
option_secret_key_file=
option_domain_name=
option_ip=

################################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  -h      This message
  -a FILE File Containing the API key
  -d NAME The domain name to update
  -i IP   Set the IP address manually
  -s FILE File Containing the secret key
  -S      Use the sandbox API instead of the production API

EOF
}

################################################################################
make_request() {
  local api_key=$1
  shift

  local secret_key=$1
  shift

  local http_date
  local hmac

  http_date=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")
  hmac=$(printf "%s" "$http_date" |
    openssl dgst -hmac "$secret_key" -sha1 |
    cut -d' ' -f2)

  curl \
    --verbose \
    --location \
    --header "Content-Type: application/json" \
    --header "x-dnsme-apiKey: $api_key" \
    --header "x-dnsme-requestDate: $http_date" \
    --header "x-dnsme-hmac: $hmac" \
    "$@"
}

################################################################################
get_record_id() {
  local name=$1

}

################################################################################
get_record_by_name() {
  local name=$1
  jq --arg name "$name" '.data[]|select(.name == $name)'
}

################################################################################
get_external_ip() {
  if [ -n "$option_ip" ]; then
    echo "$option_ip"
  else
    ip route get 1 | awk '{print $7;exit}'
  fi
}

################################################################################
set_domain_ip() {
  local ip=$1

  local api_key
  local secret_key
  local domain_name
  local record_name
  local domain_id
  local record_obj
  local record_id

  api_key=$(cat "$option_api_key_file")
  secret_key=$(cat "$option_secret_key_file")

  domain_name=$(sed -E 's/^[^.]+\.//' <<<"$option_domain_name")
  record_name=$(sed -E 's/^([^.]+).*$/\1/' <<<"$option_domain_name")

  domain_id=$(
    make_request \
      "$api_key" \
      "$secret_key" \
      --request GET \
      "$base_url/dns/managed/" |
      jq --arg name "$domain_name" '.data[]|select(.name == $name)|.id'
  )

  if [ -z "$domain_id" ]; then
    echo >&2 "ERROR: failed to lookup the domain ID for $domain_name"
    exit 1
  fi

  record_obj=$(
    make_request \
      "$api_key" \
      "$secret_key" \
      "$base_url/dns/managed/$domain_id/records" |
      jq --arg name "$record_name" '.data[]|select(.name == $name)'
  )

  if [ -z "$record_obj" ]; then
    echo >&2 "ERROR: failed to lookup record ID for $record_name"
    exit 1
  fi

  record_id=$(jq '.id' <<<"$record_obj")

  if [ -z "$record_id" ]; then
    echo >&2 "ERROR: failed to lookup record ID for $record_name"
    exit 1
  fi

  record_obj=$(
    jq --arg value "$ip" \
      '.value = $value' <<<"$record_obj"
  )

  if [ -z "$record_obj" ]; then
    echo >&2 "ERROR: failed to update the VALUE field"
    exit 1
  fi

  make_request \
    "$api_key" \
    "$secret_key" \
    --request PUT \
    --data-raw "$record_obj" \
    "$base_url/dns/managed/$domain_id/records/$record_id"
}

################################################################################
main() {
  local actual_ip
  local cached_ip=""

  if [ -z "$option_api_key_file" ] || [ ! -r "$option_api_key_file" ]; then
    echo >&2 "ERROR: missing API key file"
    exit 1
  fi

  if [ -z "$option_secret_key_file" ] || [ ! -r "$option_secret_key_file" ]; then
    echo >&2 "ERROR: missing secret key file"
    exit 1
  fi

  if [ -z "$option_domain_name" ]; then
    echo >&2 "ERROR: missing domain name"
    exit 1
  fi

  actual_ip=$(get_external_ip)

  if [ -r "$cache_file" ]; then
    cached_ip=$(head -1 "$cache_file")
  fi

  if [ "$actual_ip" != "$cached_ip" ]; then
    echo "=> Updating IP for $option_domain_name to $actual_ip"
    set_domain_ip "$actual_ip"
    echo "$actual_ip" >"$cache_file"
  fi
}

################################################################################
while getopts "ha:d:i:s:S" o; do
  case "${o}" in
  h)
    usage
    exit
    ;;

  a)
    option_api_key_file=$OPTARG
    ;;

  d)
    option_domain_name=$OPTARG
    ;;

  i)
    option_ip=$OPTARG
    ;;

  s)
    option_secret_key_file=$OPTARG
    ;;

  S)
    base_url="https://api.sandbox.dnsmadeeasy.com/V2.0"
    ;;

  *)
    exit 1
    ;;
  esac
done

shift $((OPTIND - 1))
main
