# This is an old image, kept only for backward compatibility.
# Use "latest", instead.
#
# x86_64: use jessie ; arm64: use xenial
FROM buildpack-deps:jessie 
RUN apt-get update && apt-get install -y sudo
RUN apt-get install -y uuid-dev
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers 
USER racket
WORKDIR /home/racket
RUN sudo chown racket .
ENTRYPOINT ["/bin/bash"]
