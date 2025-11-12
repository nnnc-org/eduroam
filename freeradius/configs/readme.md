# Configs

These are the default configurations copied to the container on build. You can override these configurations by mounting a volume to the container like so:

```yaml
services:
  freeradius:
    image: ghcr.io/nnnc-org/freeradius:latest
    volumes:
      - ./default-server.conf:/etc/freeradius/sites-enabled/default
```

## Templates Directory

The templates directory contains configuration files that are used to generate the final configuration at runtime. Most of these files contain environment variables that are replaced with the actual values at runtime.
