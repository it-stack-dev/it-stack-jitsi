# Dockerfile — IT-Stack JITSI wrapper
# Module 08 | Category: collaboration | Phase: 2
# Base image: jitsi/web:stable

FROM jitsi/web:stable

# Labels
LABEL org.opencontainers.image.title="it-stack-jitsi" \
      org.opencontainers.image.description="Jitsi video conferencing" \
      org.opencontainers.image.vendor="it-stack-dev" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/it-stack-dev/it-stack-jitsi"

# Copy custom configuration and scripts
COPY src/ /opt/it-stack/jitsi/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
