FROM ubuntu:bionic as ubuntu-build
RUN apt-get update && \
    apt-get -y install \
        build-essential \
        git \
        libnuma-dev

ARG DPDK_VER='master'
ENV DPDK_DIR='/dpdk'
ENV RTE_TARGET='x86_64-native-linuxapp-gcc'
RUN git clone -b $DPDK_VER -q --depth 1 http://dpdk.org/git/dpdk-stable $DPDK_DIR 2>&1
RUN cd ${DPDK_DIR} && \
    sed -ri 's,(IGB_UIO=).*,\1n,' config/common_linux* && \
    sed -ri 's,(KNI_KMOD=).*,\1n,' config/common_linux* && \
    make config T=x86_64-native-linuxapp-gcc && \
    make -j $CPUS
ENV PATH="$PATH:$DPDK_DIR/build/app/"
