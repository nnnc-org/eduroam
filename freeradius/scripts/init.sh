#!/usr/bin/env bash

set -e

PATH=/opt/sbin:/opt/bin:$PATH
export PATH

[ "$DEBUG" ] && set -x

echo "$@"

# func to print header
print_header() {
    echo "--------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------"
}

# client setup (optional)
if [ "${SETUP_CLIENTS}" == 1 ]; then
    print_header "Setup FreeRADIUS: clients.conf"

    # loop through all env vars starting with RAD_CLIENT_
    for var in "${!RAD_CLIENT_@}"; do
        declare -n ref=$var

        # only if var does not contain ADDR or SECRET, and ref is not empty
        if [[ ! $var == *_ADDR ]] && [[ ! $var == *_SECRET ]] && [ ! -z "$ref" ]; then
            # check if RAD_CLIENT is already in clients.conf
            if grep -q "client $ref" /etc/raddb/clients.conf; then
                continue
            fi

            echo "Setup FreeRADIUS: Appending '$ref' to clients.conf"
            declare -n ref_ADDR=${var}_ADDR
            declare -n ref_SECRET=${var}_SECRET

            echo -e "\nclient $ref {" >> /etc/raddb/clients.conf
            echo "    ipaddr = $ref_ADDR" >> /etc/raddb/clients.conf
            echo "    secret = $ref_SECRET" >> /etc/raddb/clients.conf
            echo "}" >> /etc/raddb/clients.conf
        fi
    done

    # eduroam client setup
    for var in "${!EDUROAM_CLIENT_@}"; do
        declare -n ref=$var

        # only if var does not contain ADDR or SECRET, and ref is not empty
        if [[ ! $var == *_ADDR ]] && [[ ! $var == *_SECRET ]] && [ ! -z "$ref" ]; then
            echo "Setup FreeRADIUS: Appending '$ref' to clients.conf"
            declare -n ref_ADDR=${var}_ADDR
            declare -n ref_SECRET=${var}_SECRET

            echo -e "\nclient $ref {" >> /etc/raddb/clients.conf
            echo "    ipaddr = $ref_ADDR" >> /etc/raddb/clients.conf
            echo "    secret = $ref_SECRET" >> /etc/raddb/clients.conf
            echo "}" >> /etc/raddb/clients.conf
        fi
    done
fi

if [ "${SETUP_PROXY}" == 1 ]; then
    print_header "Setup FreeRADIUS: proxy.conf"

    [ -z "$DOMAIN" ] && echo "DOMAIN env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR1_IPADDR" ] && echo "EDUROAM_FLR1_IPADDR env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR1_SECRET" ] && echo "EDUROAM_FLR1_SECRET env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR2_IPADDR" ] && echo "EDUROAM_FLR2_IPADDR env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR2_SECRET" ] && echo "EDUROAM_FLR2_SECRET env variable not defined! Exiting..." && exit 1

    cat > /etc/raddb/proxy.conf << EOL
proxy server {
	default_fallback = no
}

## eduroam config
home_server eduroam_flr_server_1 {
	type = auth
	ipaddr = $EDUROAM_FLR1_IPADDR
	secret = $EDUROAM_FLR1_SECRET
	port = 1812
}

home_server eduroam_flr_server_2 {
	type = auth
	ipaddr = $EDUROAM_FLR2_IPADDR
	secret = $EDUROAM_FLR2_SECRET
	port = 1812
}

home_server_pool EDUROAM {
    type = fail-over
    home_server = eduroam_flr_server_1

	# Only uncomment if there are two FLRS
	home_server = eduroam_flr_server_2
}

realm LOCAL {
}

realm ${DOMAIN,,} {
  authhost = LOCAL
  accthost = LOCAL
}

# null realm - allow here so we don't proxy inner tunnel
realm NULL {
  authhost = LOCAL
  accthost = LOCAL
}

# setup eduroam as default realm
realm DEFAULT {
	auth_pool = EDUROAM
	accthost = LOCAL
	nostrip
}
EOL
fi


print_header 'Configuring FreeRADIUS: logfiles'

# make sure linelogs exist with appropriate permissions
mkdir -p /var/log/freeradius
touch /var/log/freeradius/linelog-access
touch /var/log/freeradius/linelog-accounting
#chown freerad:freerad /var/log/freeradius -R
chmod 664 /var/log/freeradius -R

# certificate management script - provision certs
/scripts/cert-renew.sh

#/docker-entrypoint.sh "$@"
supervisord -c /etc/supervisord.conf
