# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build-doc:latest .
# 
#  docker pull --platform linux/amd64 racket/distro-build-doc:latest
#  docker image tag racket/distro-build-doc:latest racket/distro-build-doc:x86_64-linux
#  docker push racket/distro-build-doc:x86_64-linux
#
#  docker pull --platform linux/arm64/v8 racket/distro-build-doc:latest
#  docker image tag racket/distro-build-doc:latest racket/distro-build-doc:aarch64-linux
#  docker push racket/distro-build-doc:aarch64-linux
#
#
FROM racket/distro-build:debian12
USER root
RUN apt-get update && apt-get install -y texlive texlive-latex-extra texlive-fonts-recommended texlive-fonts-extra texlive-lang-cjk
USER racket
