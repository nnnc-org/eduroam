#!/bin/bash

#exit 0

PEAP_FULLCHAIN="/certs/peap/fullchain.pem"
PEAP_KEY="/certs/peap/server.key"

EAP_CERT="/certs/eap/server.crt"
EAP_KEY="/certs/eap/server.key"
EAP_CA="/certs/eap/ca.pem"

STEPPATH="/home/step"
export STEPPATH

print_header() {
    echo "--------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------"
}

extract_traefik_cert() {
    local domain="$1"
    local acme_file="$2"
    local out_dir="$3"

    mkdir -p "$out_dir"

    jq -r --arg domain "$domain" '.le.Certificates[] | select(.domain.main==$domain) | .certificate' "$acme_file" \
        | base64 -d > "$out_dir/fullchain.pem"

    jq -r --arg domain "$domain" '.le.Certificates[] | select(.domain.main==$domain) | .key' "$acme_file" \
        | base64 -d > "$out_dir/server.key"
}

wait_for_traefik_cert() {
    local domain="$1"
    local acme_file="$2"
    local interval="${3:-5}"   # check every 5 seconds by default

    until jq -e --arg domain "$domain" '.le.Certificates[] | select(.domain.main == $domain)' "$acme_file" > /dev/null 2>&1; do
        echo "Waiting for certificate for domain '$domain' to appear in $acme_file..."
        sleep "$interval"
    done
    echo "Certificate for '$domain' found in $acme_file."
}

generate_step_cert() {
    local domain="$1"
    local output_dir="$2"

    mkdir -p "$output_dir"

    # Defaults
    local provisioner_name="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-admin}"

    step ca certificate --ca-url https://stepca:9000 --root /home/step/certs/root_ca.crt \
                        --password-file "${STEPPATH}/password" \
                        --provisioner "${provisioner_name}" \
                        --provisioner-password-file "${STEPPATH}/secrets/password" \
                        --not-after=8760h \
                        "$domain" \
                        "$output_dir/server.crt" \
                        "$output_dir/server.key"

    if [ $? -ne 0 ]; then
        echo "Failed to generate certificate"
        return 1
    fi

    echo "Certificate and key have been generated at:"
    echo "  $output_dir/server.crt"
    echo "  $output_dir/server.key"
}


fix_permissions() {
    print_header "Fixing Cert Permissions"
    #chown -R root:freerad /certs
    chmod 640 /certs/eap/*
    chmod 640 /certs/peap/*
}

compare_cert() {
    local certA="$1"
    local certB="$2"

    if ! cmp -s $certA $certB; then
        echo "Certificates are different, installing new ones"
        cp $certA $certB
    fi
}

restart_freeradius() {
    # check if cert files have been updated recently (within last 12 hours) using stat
    # if so, restart FreeRADIUS
    local dir="/certs"
    if find "$dir" -type f -mmin -720 | grep -q . && pgrep -x radiusd >/dev/null; then
        print_header "Certificates have been updated, restarting FreeRADIUS"
        supervisorctl restart all:freeradius
    fi
}

print_header "Starting Certificate Management Script"

# Check if server cert has been created yet
if [ ! -f "/certs/eap/server.crt" ] || [ ! -f "/certs/eap/server.key" ]; then
    echo "No EAP certificate/key found in /certs - generating cert from stepca"
    generate_step_cert "eduroam.$DOMAIN" /certs/eap

    echo "Copying root & intermediate CA to /certs/eap/ca.pem"
    cat /home/step/certs/root_ca.crt /home/step/certs/intermediate_ca.crt > /certs/eap/ca.pem
else
    echo "EAP certificate/key found in /certs - skipping generation" #TODO: handle renewal :/
fi

wait_for_traefik_cert "eduroam.$DOMAIN" "/letsencrypt/acme.json"
extract_traefik_cert "eduroam.$DOMAIN" "/letsencrypt/acme.json" "/tmp/peap"
mkdir -p /certs/peap
compare_cert "/tmp/peap/fullchain.pem" "$PEAP_FULLCHAIN"
compare_cert "/tmp/peap/server.key" "$PEAP_KEY"

fix_permissions
restart_freeradius
