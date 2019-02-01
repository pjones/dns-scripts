#!/bin/sh

################################################################################
set -e

################################################################################
export PATH=@extra_path@:$PATH

################################################################################
production_url_base="https://api.dnsmadeeasy.com/V2.0"
sandbox_url_base="https://api.sandbox.dnsmadeeasy.com/V2.0"

################################################################################
url_base=$sandbox_url_base
api_request_date=""
api_request_hmac=""
full_domain_name=${CERTBOT_DOMAIN:=test.com}
validation_value=${CERTBOT_VALIDATION:=test}

################################################################################
option_api_key=""
option_api_secret=""
option_delete=0

################################################################################
usage () {
cat <<EOF
Usage: dnsme-letsencript.sh [options]

  -d      Delete the validation record instead of creating it
  -h      This message
  -k KEY  Your API key
  -p      Make a production call instead of a sandbox call
  -s SEC  Your API secret
EOF
}

################################################################################
while getopts "dhk:ps:" o; do
  case "${o}" in
    d) option_delete=1
       ;;

    h) usage
       exit
       ;;

    k) option_api_key=$OPTARG
       ;;

    p) url_base=$production_url_base
       ;;

    s) option_api_secret=$OPTARG
       ;;

    *) exit 1
       ;;
  esac
done

shift $((OPTIND-1))

################################################################################
die() {
  >&2 echo "ERROR: " "$@"
  exit 1
}

################################################################################
make_hmac() {
  api_request_date=$(date --utc "+%a, %d %b %Y %H:%M:%S GMT")

  api_request_hmac=$(printf %s "$api_request_date" | \
                       openssl dgst -sha1 -hmac "$option_api_secret" | \
                       cut -d' ' -f2)
}

################################################################################
make_request() {
  method=$1; shift
  path=$1; shift

  make_hmac

  curl --silent \
       --request "$method" \
       --url "${url_base}${path}" \
       --header "Content-Type: application/json" \
       --header "x-dnsme-apiKey: $option_api_key" \
       --header "x-dnsme-hmac: $api_request_hmac" \
       --header "x-dnsme-requestDate: $api_request_date" \
       "$@"
}

################################################################################
get_domain_name() {
  name=$1; shift
  echo "$name" | awk -F. '{print $(NF-1)"."$NF}'
}

################################################################################
remove_domain_name() {
  name=$1; shift

  echo "$name" | \
    awk -F. '{for(i=1; i<=(NF-2); i++) printf "."$i; print "";}'
}

################################################################################
get_domain_id() {
  name=$1; shift
  domain=$(get_domain_name "${name}")

  make_request GET "/dns/managed/id/${domain}" | \
    jq --raw-output .id
}

################################################################################
get_record_id() {
  domain_id=$1; shift
  name=$1; shift

  make_request GET "/dns/managed/${domain_id}/records" \
               --data-urlencode "recordName=${name}" \
               --data-urlencode "type=TXT" \
               --get | \
    jq --raw-output '.data[0].id'
}

################################################################################
create_record() {
  domain_id=$1; shift
  name=$1; shift
  value=$1; shift

  make_request POST "/dns/managed/${domain_id}/records/" \
               --data-binary @- > /dev/null <<EOF
{"name":"${name}","type":"TXT","value":"${value}","ttl":120}
EOF

}

################################################################################
delete_record() {
  domain_id=$1; shift
  record_id=$1; shift

  make_request DELETE "/dns/managed/${domain_id}/records/${record_id}"
}

################################################################################
make_record_name() {
  hostname=$1; shift
  domain=$(remove_domain_name "$hostname")
  echo "_acme-challenge${domain}"
}

################################################################################
domain_id=$(get_domain_id "$full_domain_name")
record_name=$(make_record_name "$full_domain_name")

if [ "$option_delete" -eq 1 ]; then
  record_id=$(get_record_id "$domain_id" "$record_name")

  if [ -z "$record_id" ] || [ "$record_id" = "null" ]; then
    die "expected to find record ID for $record_name but got NULL"
  fi

  delete_record "$domain_id" "$record_id"
else
  create_record "$domain_id" "$record_name" "$validation_value"
  sleep 25 # Wait for DNS to propagate.
fi
