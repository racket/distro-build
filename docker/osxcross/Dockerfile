# Build and push with
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:osxcross-x86_64 --build-arg MACOS_SDK_VERSION=10.9 --build-arg MACOS_MIN_VERSION=10.9 .
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:osxcross-aarch64 --build-arg MACOS_SDK_VERSION=11.1 --build-arg MACOS_MIN_VERSION=11.0 .
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:osxcross-i386 --build-arg MACOS_SDK_VERSION=10.6 --build-arg MACOS_MIN_VERSION=10.6 --build-arg OSXCROSS_BRANCH=master .
#  docker buildx build --push --platform linux/arm64/v8,linux/amd64 --tag racket/distro-build:osxcross-ppc --build-arg MACOS_SDK_VERSION=10.5 --build-arg MACOS_MIN_VERSION=10.5 --build-arg OSXCROSS_BRANCH=ppc-test .
# (and try `docker buildx create --use desktop-linux` first if that fails)

# Or just build with
#  docker build -t racket/distro-build:osxcross-x86_64 --build-arg MACOS_SDK_VERSION=10.9 --build-arg MACOS_MIN_VERSION=10.9 .
#  docker build -t racket/distro-build:osxcross-aarch64 --build-arg MACOS_SDK_VERSION=11.1 --build-arg MACOS_MIN_VERSION=11.0 .
#  docker build -t racket/distro-build:osxcross-i386 --build-arg MACOS_SDK_VERSION=10.6 --build-arg MACOS_MIN_VERSION=10.6 --build-arg OSXCROSS_BRANCH=master .
#  docker build -t racket/distro-build:osxcross-ppc --build-arg MACOS_SDK_VERSION=10.5 --build-arg MACOS_MIN_VERSION=10.5 --build-arg OSXCROSS_BRANCH=ppc-test .

FROM racket/distro-build:osxcross-base

# The `osxcross` project provides cross compilers for Mac OS. This is the
# part that depends on the target platform, so it's parameterized by
# argument variables

ARG MACOS_SDK_VERSION="10.9"
ARG MACOS_MIN_VERSION="10.9"
ARG OSXCROSS_BRANCH="2.0-llvm-based"

ENV RKT_MACOS_SDK_VERSION=${MACOS_SDK_VERSION}
ENV RKT_MACOS_MIN_VERSION=${MACOS_MIN_VERSION}
ENV RKT_OSXCROSS_BRANCH=${OSXCROSS_BRANCH}

WORKDIR /
RUN git clone --filter=blob:none --branch ${RKT_OSXCROSS_BRANCH} https://github.com/tpoechtrager/osxcross
RUN cd osxcross/tarballs && wget https://users.cs.utah.edu/~mflatt/tmp/MacOSX${RKT_MACOS_SDK_VERSION}.sdk.tar.xz
WORKDIR /osxcross
# A manual link seems needed to make "./build.sh" happy
RUN ln -s ld64.lld-14 /bin/ld64.lld
RUN env OSX_VERSION_MIN=${RKT_MACOS_MIN_VERSION} UNATTENDED=y ./build.sh

ENV PATH="$PATH:/osxcross/target/bin"

RUN if [ "$RKT_OSXCROSS_BRANCH" = "ppc-test" ] ; then mv ./target/SDK/MacOSX10.5.sdk/usr/include/c++/4.0.0 ./target/SDK/MacOSX10.5.sdk/usr/include/c++/4.0.0.dontuse ; fi
RUN if [ "$RKT_OSXCROSS_BRANCH" = "ppc-test" ] ; then DEBUG=1 OCDEBUG=1 UNATTENDED=1 GCC_VERSION=5.5.0 POWERPC=1 CXXFLAGS="-std=c++14" ./build_gcc.sh ; fi

USER racket
WORKDIR /home/racket
ENTRYPOINT ["/bin/bash"]
