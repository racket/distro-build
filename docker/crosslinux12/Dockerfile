# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosslinux-riscv64 --build-arg ARCH=riscv64 .
#   (try `docker buildx create --use desktop-linux` first if that fails)

# Or just build with
#  docker build -t racket/distro-build:crosslinux-riscv64 --build-arg ARCH=riscv64 .

FROM buildpack-deps:bookworm

ARG ARCH="x86_64"
ARG PATH_EXTRA=""
ENV RKT_ARCH=${ARCH}

RUN apt-get update && apt-get install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers

RUN if [ ${RKT_ARCH} = "riscv64" ]; then apt install -y gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu; fi

USER racket
WORKDIR /home/racket
RUN chown racket .
RUN git config --global --add safe.directory /docker-mnt/server-repo
ENTRYPOINT ["/bin/bash"]
