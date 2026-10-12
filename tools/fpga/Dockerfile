FROM --platform=linux/amd64 ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 libsm6 libice6 libxext6 libxrender1 libxft2 libxt6 \
    libxmu6 libxi6 libxtst6 libxfixes3 libxcursor1 libxinerama1 \
    libxrandr2 libxdamage1 libxcomposite1 libfontconfig1 libfreetype6 \
    libgl1 libglu1-mesa zlib1g libpng16-16 libnss3 libxshmfence1 \
    ca-certificates locales make file perl-base && \
    locale-gen en_US.UTF-8 && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
