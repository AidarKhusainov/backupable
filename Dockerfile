FROM docker:29.8.1-cli-alpine3.24

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    curl \
    findutils \
    grep \
    msmtp \
    mutt \
    sed \
    tzdata \
    util-linux \
    zip

WORKDIR /app

COPY backupable.sh /app/backupable.sh
COPY lib /app/lib
COPY docker /app/docker

RUN chmod 0755 /app/backupable.sh /app/docker/entrypoint.sh /app/docker/scheduler.sh /app/docker/healthcheck.sh \
    && ln -s /app/docker/entrypoint.sh /usr/local/bin/backupable \
    && mkdir -p /var/lib/backupable/jobs /var/lib/backupable/state \
    && chmod 0700 /var/lib/backupable /var/lib/backupable/jobs /var/lib/backupable/state

ENV BACKUPABLE_BACKUP_DIR=/var/lib/backupable/jobs \
    BACKUPABLE_STATE_DIR=/var/lib/backupable/state \
    BACKUPABLE_SCHEDULER_MODE=internal \
    BACKUPABLE_POLL_SECONDS=60

VOLUME ["/var/lib/backupable"]

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["run"]

HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/app/docker/healthcheck.sh"]
