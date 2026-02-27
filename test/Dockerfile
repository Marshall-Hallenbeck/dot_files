ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

# Bootstrap dependencies needed before install scripts run
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    wget \
    curl \
    ca-certificates \
    python3 \
    lsb-release \
    git \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Allow chsh without password in Docker (no TTY for PAM auth)
RUN printf 'auth sufficient pam_rootok.so\nauth sufficient pam_permit.so\n' > /etc/pam.d/chsh

# Create test user with passwordless sudo
RUN useradd -m -s /bin/bash testuser \
    && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

COPY . /repo
COPY test/run-test.sh /usr/local/bin/run-test.sh
RUN chmod +x /usr/local/bin/run-test.sh

USER testuser
WORKDIR /home/testuser
ENTRYPOINT ["/usr/local/bin/run-test.sh"]
