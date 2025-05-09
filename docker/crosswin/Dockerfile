# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosswin .
# (and try `docker buildx create --use desktop-linux` first if that fails)

# Or just build with
#  docker build -t racket/distro-build:crosswin .

FROM buildpack-deps:buster
RUN apt update && apt install -y wget xz-utils nsis mingw-w64
RUN wget https://github.com/mstorsjo/llvm-mingw/releases/download/20220323/llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar.xz
RUN xz --decompress llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar.xz && tar xf llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar && mv llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m` llvm && rm llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar
RUN apt install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers

WORKDIR /tmp
# patched NSIS to drop `msync`:
RUN wget https://users.cs.utah.edu/~mflatt/tmp/nsis-3.11-src.tar.gz
RUN tar xzf nsis-3.11-src.tar.gz
WORKDIR /tmp/nsis-3.11-src
RUN apt install scons
RUN python3 /usr/bin/scons SKIPSTUBS=all SKIPPLUGINS=all SKIPUTILS=all SKIPMISC=all NSIS_CONFIG_CONST_DATA=no PREFIX=/usr install-compiler

USER racket
WORKDIR /home/racket
RUN sudo chown racket .

# Putting "/llvm/bin" second means that msvcrt `x86_64-w64-...` and
# `i386-w64-...` executables are found first, then `aarch64-w64-...`
# from the UCRT installation.
ENV PATH="${PATH}:/llvm/bin"

ENTRYPOINT ["/bin/bash"]
