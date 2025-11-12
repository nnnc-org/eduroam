ARG FREERADIUS_VERSION=3.2.8

ARG STEP_VERSION=0.28.7

FROM smallstep/step-cli:${STEP_VERSION} AS stepcli

# build eapol_test for testing purposes
FROM freeradius/freeradius-server:${FREERADIUS_VERSION}-alpine AS build
RUN apk add git gcc make openssl openssl-dev libc-dev talloc-dev pcre-dev libidn-dev krb5-dev samba-dev curl-dev json-c-dev openldap-dev unbound-dev linux-headers && \
    mkdir /build && cd /build && \
    git clone --depth 1 --no-single-branch https://github.com/FreeRADIUS/freeradius-server.git
# sed fixes error on alpine systems
RUN cd /build/freeradius-server/scripts/ci/ && \
    sed -i 's/cp -n/cp/g' eapol_test-build.sh && \
    ./eapol_test-build.sh

FROM freeradius/freeradius-server:${FREERADIUS_VERSION}-alpine

COPY --from=build /build/freeradius-server/scripts/ci/eapol_test/eapol_test /usr/local/bin/

# copy step cli
COPY --from=stepcli /usr/local/bin/step /usr/local/bin/step

# Install Dependencies
RUN apk add bash gettext libidn freeradius-radclient supervisor jq curl

# Change defaults
# 1. Send logs to stdout by default
# 2. Set require_message_authenticator = true for localhost client
# 3. Enable cache-auth & rest module
RUN sed -i 's/auth = no/auth = yes/g' /etc/raddb/radiusd.conf && \
    sed -i 's/destination = files/destination = stdout/g' /etc/raddb/radiusd.conf && \
    ln -s /etc/raddb/mods-available/cache_auth /etc/raddb/mods-enabled/cache_auth && \
    echo "rest {}" > /etc/raddb/mods-enabled/rest


# Copy custom configs and scripts
COPY configs/raddb/ /etc/raddb/
COPY configs/supervisord.conf /etc/supervisord.conf
COPY scripts/ /scripts

ENTRYPOINT ["/scripts/init.sh"]
