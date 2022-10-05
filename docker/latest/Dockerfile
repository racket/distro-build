# Build and push with
#  docker buildx build --platform linux/arm64/v8,linux/386,linux/amd64 --tag racket/distro-build:latest .
# 
#  docker pull --platform linux/386 racket/distro-build:latest
#  docker image tag racket/distro-build:latest racket/distro-build:i386-linux
#  docker push racket/distro-build:i386-linux
#
#  docker pull --platform linux/am664 racket/distro-build:latest
#  docker image tag racket/distro-build:latest racket/distro-build:x86_64-linux
#  docker push racket/distro-build:x86_64-linux
#
#  docker pull --platform linux/arm64/v8 racket/distro-build:latest
#  docker image tag racket/distro-build:latest racket/distro-build:aarch64-linux
#  docker push racket/distro-build:aarch64-linux
#
#
FROM buildpack-deps:stretch
RUN apt-get update && apt-get install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers 
USER racket
WORKDIR /home/racket
RUN sudo chown racket .
ENTRYPOINT ["/bin/bash"]
