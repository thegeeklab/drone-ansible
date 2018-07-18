FROM plugins/base:amd64

LABEL maintainer="Drone.IO Community <drone-dev@googlegroups.com>" \
  org.label-schema.name="Drone Ansible" \
  org.label-schema.vendor="Drone.IO Community" \
  org.label-schema.schema-version="1.0"

RUN apk add --no-cache bash git curl ansible py-pip py-requests && \
  pip install -U pip

ADD release/linux/amd64/drone-ansible /bin/
ENTRYPOINT ["/bin/drone-ansible"]
