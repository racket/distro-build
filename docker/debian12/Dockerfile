# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:debian12 .
#  # (try `docker buildx create --use desktop-linux` first if that fails)
#
FROM buildpack-deps:bookworm
RUN apt-get update && apt-get install -y sudo
RUN apt install -y gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers
USER racket
WORKDIR /home/racket
RUN chown racket .
ENTRYPOINT ["/bin/bash"]
