FROM killua99/node-ruby as assets-compiled

COPY mastodon-upstream /tmp/mastodon-build

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        gcc \
        g++ \
        ffmpeg \
        file \
        imagemagick \
        libicu63 \
        libssl1.1 \
        libpq5 \
        libprotobuf-lite17 \
        libicu-dev \
        libidn11 \
        libyaml-0-2 \
        tzdata \
        libreadline7 \
        make \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    \
    mkdir -p /opt/mastodon; \
    cp /tmp/mastodon-build/Gemfile* /opt/mastodon/; \
    cp /tmp/mastodon-build/package.json /opt/mastodon/; \
    cp /tmp/mastodon-build/yarn.lock /opt/mastodon/; \
    cd /opt/mastodon; \
    bundle config set deployment 'true'; \
    bundle config set without 'development test'; \
    bundle install -j$(nproc); \
    yarn install --pure-lockfile;

FROM assets-compiled AS final

# Copy mastodon
COPY --chown=991:991 mastodon-upstream /opt/mastodon
COPY --from=assets-compiled --chown=991:991 /opt/mastodon /opt/mastodon

ARG UID=991
ARG GID=991

# Compiling assets.
RUN set -eux; \
    \
    echo "Etc/UTC" > /etc/localtime; \
    addgroup --gid ${GID} mastodon; \
    useradd -m -u ${UID} -g ${GID} -d /opt/mastodon mastodon; \
    echo "mastodon:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 | mkpasswd -s -m sha-256`" | chpasswd; \
    chown -R mastodon:mastodon /opt/mastodon; \
    cd /opt/mastodon; \
    ln -s /opt/mastodon /mastodon

# Run mastodon services in prod mode
ENV RAILS_ENV="production"
ENV NODE_ENV="production"

# Tell rails to serve static files
ENV RAILS_SERVE_STATIC_FILES="true"
ENV BIND="0.0.0.0"
ENV PATH="${PATH}:/opt/mastodon/bin"

# Set the run user
USER mastodon

# Precompile assets
RUN set -eux; \
    \
    cd ~ \
    OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile; \
    yarn cache clean

# Set the work dir and the container entry point
WORKDIR /opt/mastodon

ENTRYPOINT [ "/usr/bin/tini", "--" ]
