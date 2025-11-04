#!/bin/bash
set -eo pipefail

# Updated from https://github.com/smallstep/certificates/blob/25e35aa0ad32d340fd9a6e04d30370f2539d956e/docker/entrypoint.sh

export STEPPATH=$(step path)

# List of env vars required for step ca init
declare -ra REQUIRED_INIT_VARS=(DOCKER_STEPCA_INIT_NAME DOCKER_STEPCA_INIT_DNS_NAMES)

# Ensure all env vars required to run step ca init are set.
function init_if_possible () {
    local missing_vars=0
    for var in "${REQUIRED_INIT_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars=1
        fi
    done
    if [ ${missing_vars} = 1 ]; then
        >&2 echo "there is no ca.json config file; please run step ca init, or provide config parameters via DOCKER_STEPCA_INIT_ vars"
    else
        step_ca_init "${@}"
    fi
}

function generate_password () {
    set +o pipefail
    < /dev/urandom tr -dc A-Za-z0-9 | head -c40
    echo
    set -o pipefail
}

# Initialize a CA if not already initialized
function step_ca_init () {
    DOCKER_STEPCA_INIT_PROVISIONER_NAME="${DOCKER_STEPCA_INIT_PROVISIONER_NAME:-admin}"
    DOCKER_STEPCA_INIT_ADMIN_SUBJECT="${DOCKER_STEPCA_INIT_ADMIN_SUBJECT:-step}"
    DOCKER_STEPCA_INIT_ADDRESS="${DOCKER_STEPCA_INIT_ADDRESS:-:9000}"

    local -a setup_args=(
        --name "${DOCKER_STEPCA_INIT_NAME}"
        --dns "${DOCKER_STEPCA_INIT_DNS_NAMES}"
        --provisioner "${DOCKER_STEPCA_INIT_PROVISIONER_NAME}"
        --password-file "${STEPPATH}/password"
        --provisioner-password-file "${STEPPATH}/provisioner_password"
        --address "${DOCKER_STEPCA_INIT_ADDRESS}"
    )
    if [ -n "${DOCKER_STEPCA_INIT_PASSWORD_FILE}" ]; then
        cat < "${DOCKER_STEPCA_INIT_PASSWORD_FILE}" > "${STEPPATH}/password"
        cat < "${DOCKER_STEPCA_INIT_PASSWORD_FILE}" > "${STEPPATH}/provisioner_password"
    elif [ -n "${DOCKER_STEPCA_INIT_PASSWORD}" ]; then
        echo "${DOCKER_STEPCA_INIT_PASSWORD}" > "${STEPPATH}/password"
        echo "${DOCKER_STEPCA_INIT_PASSWORD}" > "${STEPPATH}/provisioner_password"
    else
        generate_password > "${STEPPATH}/password"
        generate_password > "${STEPPATH}/provisioner_password"
    fi
    if [ "${DOCKER_STEPCA_INIT_SSH}" == "true" ]; then
        setup_args=("${setup_args[@]}" --ssh)
    fi
    if [ "${DOCKER_STEPCA_INIT_ACME}" == "true" ]; then
        setup_args=("${setup_args[@]}" --acme)
    fi
    if [ "${DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT}" == "true" ]; then
        setup_args=("${setup_args[@]}" --remote-management
            --admin-subject "${DOCKER_STEPCA_INIT_ADMIN_SUBJECT}"
        )
    fi
    step ca init "${setup_args[@]}"
   	echo ""

    # Remove Default CA, do some RSA stuff
    echo "Removing default CA and creating new RSA Root and Intermediate CAs..."
    rm ./certs/root_ca.crt ./secrets/root_ca_key ./certs/intermediate_ca.crt ./secrets/intermediate_ca_key
    ## build root CA
    step certificate create "$DOCKER_STEPCA_INIT_NAME - Root" ./certs/root_ca.crt ./secrets/root_ca_key \
	            --kty RSA \
			    --not-after 87660h \
			    --size 3072 \
                --password-file "${STEPPATH}/password" \
			    --profile=root-ca
    ## build intermediate ca
    step certificate create "$DOCKER_STEPCA_INIT_NAME - Intermediate" ./certs/intermediate_ca.crt ./secrets/intermediate_ca_key \
	            --ca ./certs/root_ca.crt \
			    --ca-key ./secrets/root_ca_key \
                --ca-password-file "${STEPPATH}/password" \
			    --kty RSA \
			    --not-after 87660h \
			    --size 3072 \
                --password-file "${STEPPATH}/password" \
			    --profile=intermediate-ca

    if [[ "${DOCKER_STEPCA_INIT_SCEP:-false}" == "true" ]] && \
       [[ -n "${DOCKER_STEPCA_INIT_SCEP_NAME:-}" ]] && \
       [[ -n "${DOCKER_STEPCA_INIT_SCEP_CHALLENGE:-}" ]]; then

        echo "Creating SCEP provisioner: ${DOCKER_STEPCA_INIT_SCEP_NAME}"

        step ca provisioner add "${DOCKER_STEPCA_INIT_SCEP_NAME}" \
             --type SCEP \
             --challenge "${DOCKER_STEPCA_INIT_SCEP_CHALLENGE}" \
             --encryption-algorithm-identifier 2
	     #--include-root # breaks windows renewal, but needed for some macs version?

        if [[ "${DOCKER_STEPCA_INIT_INSECURE:-false}" == "true" ]]; then
            sed -i 's/"insecureAddress": *"",/"insecureAddress": ":9001",/' ${STEPPATH}/config/ca.json
        fi
    fi

    ## check if USER_DOMAIN is set
    if [ -n "${DOCKER_STEPCA_INIT_USER_DOMAIN}" ]; then
        echo "Limiting x509 certificate generation to email domain: ${DOCKER_STEPCA_INIT_USER_DOMAIN}"
        #step ca policy authority x509 allow email "@${DOCKER_STEPCA_INIT_USER_DOMAIN}"
        tmpfile="$(mktemp)"
        jq --arg domain "@${DOCKER_STEPCA_INIT_USER_DOMAIN}" '
          .authority.policy.x509.allow.email |=
          (if . == null then [$domain]
           else (. + [$domain] | unique)
           end)
        ' ${STEPPATH}/config/ca.json > "$tmpfile" && mv "$tmpfile" ${STEPPATH}/config/ca.json
    fi

    if [ "${DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT}" == "true" ]; then
        echo "👉 Your CA administrative username is: ${DOCKER_STEPCA_INIT_ADMIN_SUBJECT}"
    fi

    # print CA thumbprints
    echo "👉 Your Root CA thumbprint is: $( step certificate fingerprint ./certs/root_ca.crt --sha1 --insecure )"
    echo "👉 Your Intermediate CA thumbrint is: $( step certificate fingerprint ./certs/intermediate_ca.crt --sha1 --insecure )"

    echo "👉 Your CA administrative password is: $(< $STEPPATH/provisioner_password )"
    echo "🤫 This will only be displayed once."
    shred -u $STEPPATH/provisioner_password
    mv $STEPPATH/password $PWDPATH
}

if [ -f /usr/sbin/pcscd ]; then
    /usr/sbin/pcscd
fi

if [ ! -f "${STEPPATH}/config/ca.json" ]; then
    init_if_possible
fi

exec "${@}"
