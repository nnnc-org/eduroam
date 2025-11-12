#!/usr/bin/env bash

# Generate the server certificate for a given domain using step cli
# Usage: ./generate_cert.sh <domain> <output_dir>

DOMAIN=$1
OUTPUT_DIR=$2

if [ -z "$DOMAIN" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: $0 <domain> <output_dir>"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# default STEPPATH
STEPPATH=${STEPPATH:-/home/step}
PROVISIONER_NAME="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-admin}"

step ca certificate --ca-url https://stepca:9000 --root /home/step/certs/root_ca.crt \
                    --password-file "${STEPPATH}/password" \
                    --provisioner "${PROVISIONER_NAME}" \
                    --provisioner-password-file "${STEPPATH}/secrets/password" \
                    --not-after=8760h \
                    "$DOMAIN" \
                    "$OUTPUT_DIR/server.crt" \
                    "$OUTPUT_DIR/server.key"

if [ $? -ne 0 ]; then
  echo "Failed to generate certificate"
  exit 1
fi

echo "Certificate and key have been generated at $OUTPUT_DIR/server.crt and $OUTPUT_DIR/server.key"
