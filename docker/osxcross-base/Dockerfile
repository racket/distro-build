# This is a shared image before an architecture-specific compiler is added to
# get a useful `racket/osxcross` variant

# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:osxcross-base .
# (and try `docker buildx create --use desktop-linux` first if that fails)

# Or just build with
#  docker build -t racket/distro-build:osxcross-base .

FROM ubuntu:22.04

ARG MACOS_SDK_VERSION="10.9"
ARG MACOS_MIN_VERSION="10.9"
ARG OSXCROSS_BRANCH="2.0-llvm-based"

RUN apt update
RUN apt install --no-install-recommends -y \
    sudo \
    bash \
    binutils-multiarch-dev \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    git \
    libbz2-dev \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev \
    liblzma-dev \
    libpsi3-dev \
    libssl-dev \
    libxml2-dev \
    libz-dev \
    lzma-dev \
    make \
    patch \
    python3 \
    uuid-dev \
    wget \
    xz-utils \
    zlib1g-dev \
    curl \
    llvm \
    lld

# Create `racket` user
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers
USER racket
WORKDIR /home/racket
RUN chown racket .
RUN git config --global --add safe.directory /docker-mnt/server-repo

# Install Rust and `rcodesign`
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="$PATH:/home/racket/.cargo/bin"
RUN cargo install apple-codesign

USER root
WORKDIR /

# The `hfsprogs` package provides `mkfs.hfsplus` for creating a
# blank HFS+ filesystem
RUN apt install -y hfsprogs

# The `libdmg-hfsplus` project provides `hfsplus` and `dmg` for filling
# and HFS+ image and converting it to a compressed ".dmg"
RUN git clone --filter=blob:none https://github.com/mflatt/libdmg-hfsplus
RUN mkdir -p libdmg-hfsplus/build
WORKDIR /libdmg-hfsplus/build
RUN cmake ..
RUN cmake --build .
RUN cmake --install .
