# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:crosswin .
FROM buildpack-deps:buster
RUN apt update && apt install -y wget xz-utils nsis mingw-w64
RUN wget https://github.com/mstorsjo/llvm-mingw/releases/download/20220323/llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar.xz
RUN xz --decompress llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar.xz && tar xf llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar && mv llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m` llvm && rm llvm-mingw-20220323-ucrt-ubuntu-18.04-`uname -m`.tar
RUN apt install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers
USER racket
WORKDIR /home/racket
RUN sudo chown racket .
ENV PATH="/llvm/bin:${PATH}"
ENTRYPOINT ["/bin/bash"]
