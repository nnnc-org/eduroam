ARG STEPCA_VERSION=0.28.4

# build eapol_test for testing purposes
FROM smallstep/step-ca:${STEPCA_VERSION}

# install jq so we can add default x509 policy
USER root
RUN apk add --no-cache jq

# update entrypoint to our modified version
COPY ./entrypoint.sh /entrypoint.sh

# switch back to step user
USER step
