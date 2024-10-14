# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/386,linux/amd64 --tag racket/distro-build:debian10 .
#  # (try `docker buildx create --use desktop-linux` first if that fails)
#
#  docker pull --platform linux/386 racket/distro-build:debian10
#  docker image tag racket/distro-build:debian10 racket/distro-build:debian10-i386-linux
#  docker push racket/distro-build:debian10-i386-linux
#
#  docker pull --platform linux/amd64 racket/distro-build:debian10
#  docker image tag racket/distro-build:debian10 racket/distro-build:debian10-x86_64-linux
#  docker push racket/distro-build:debian10-x86_64-linux
#
#  docker pull --platform linux/arm64/v8 racket/distro-build:debian10
#  docker image tag racket/distro-build:debian10 racket/distro-build:debian10-aarch64-linux
#  docker push racket/distro-build:debian10-aarch64-linux
#
#
FROM buildpack-deps:buster
RUN apt-get update && apt-get install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers
USER racket
WORKDIR /home/racket
RUN chown racket .
ENTRYPOINT ["/bin/bash"]
