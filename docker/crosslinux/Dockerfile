# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosslinux-x86_64 --build-arg ARCH=x86_64 .
#   (try `docker buildx create --use desktop-linux` first if that fails)
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosslinux-i386 --build-arg ARCH=i386 .
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosslinux-aarch64 --build-arg ARCH=aarch64 .
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosslinux-arm --build-arg ARCH=arm .
#  docker buildx build --push --platform linux/amd64 --tag racket/distro-build:crosslinux-arm-debian7 --build-arg ARCH=arm-debian7 --build-arg PATH_EXTRA=":/pi-tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin/" .

# Or just build with
#  docker build -t racket/distro-build:crosslinux-x86_64 --build-arg ARCH=x86_64 .
#  docker build -t racket/distro-build:crosslinux-i386 --build-arg ARCH=i386 .
#  docker build -t racket/distro-build:crosslinux-aarch64 --build-arg ARCH=aarch64 .
#  docker build -t racket/distro-build:crosslinux-arm --build-arg ARCH=arm .

FROM buildpack-deps:buster

ARG ARCH="x86_64"
ARG PATH_EXTRA=""
ENV RKT_ARCH=${ARCH}

RUN apt-get update && apt-get install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers

RUN if [ ${RKT_ARCH} = "x86_64" ]; then apt install -y gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu; fi
RUN if [ ${RKT_ARCH} = "i386" ]; then apt install -y gcc-i686-linux-gnu binutils-i686-linux-gnu; fi
RUN if [ ${RKT_ARCH} = "aarch64" ]; then apt install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu; fi
RUN if [ ${RKT_ARCH} = "arm" ]; then apt install -y gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf; fi

RUN if [ ${RKT_ARCH} = "arm-debian7" ]; then git clone --depth 1 https://github.com/raspberrypi/tools pi-tools; fi
ENV PATH="$PATH${PATH_EXTRA}"

USER racket
WORKDIR /home/racket
RUN chown racket .
ENTRYPOINT ["/bin/bash"]
