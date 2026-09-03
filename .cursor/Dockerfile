# Cloud Agent development image for the Maybe Rails app.
# Ruby version is pinned to match .ruby-version / Gemfile.
FROM ruby:3.4.4-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC

# System packages:
# - build-essential, git, curl, pkg-config, libpq-dev, libyaml-dev, libffi-dev: build native gems
# - postgresql, postgresql-client: local development database
# - redis-server: Sidekiq / ActiveJob backend
# - libvips: Active Storage image processing (image_processing gem)
# - nodejs, npm: Biome lint/format tooling
# - sudo: allow the non-root agent user to manage local services
RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y \
        build-essential git curl ca-certificates gnupg pkg-config \
        libpq-dev libyaml-dev libffi-dev libjemalloc2 \
        postgresql postgresql-client \
        redis-server \
        libvips \
        nodejs npm \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# Create the non-root "ubuntu" user expected by Cloud Agents, with passwordless sudo
# so start/install scripts can manage the local Postgres and Redis services.
RUN useradd --create-home --shell /bin/bash ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && usermod -aG postgres ubuntu

USER ubuntu
WORKDIR /workspace
