FROM buildpack-deps
RUN apt-get update && apt-get install -y sudo
RUN useradd --no-log-init -r -g sudo racket
RUN echo "racket ALL=(ALL) NOPASSWD: ALL " >> /etc/sudoers 
USER racket
WORKDIR /home/racket
RUN sudo chown racket .
ENTRYPOINT ["/bin/bash"]
