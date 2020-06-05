# Build multus plugin
FROM busybox AS multus
ARG MULTUS_VER=3.4.2
RUN wget -O multus.tgz https://github.com/intel/multus-cni/releases/download/v${MULTUS_VER}/multus-cni_${MULTUS_VER}_linux_amd64.tar.gz
RUN tar xvzf multus.tgz --strip-components=1 -C /bin

# Build sriov plugin
FROM golang AS sriov-cni
ARG SRIOV_CNI_VER=2.3
RUN wget -qO sriov-cni.tgz https://github.com/intel/sriov-cni/archive/v${SRIOV_CNI_VER}.tar.gz
RUN mkdir -p sriov-cni && \
    tar xzf sriov-cni.tgz --strip-components=1 -C sriov-cni && \
    cd sriov-cni && \
    make && \
    cp build/sriov /bin

# Build sriov device plugin
FROM golang AS sriov-dp
ARG SRIOV_DP_VER=3.2
RUN wget -qO sriov-dp.tgz https://github.com/intel/sriov-network-device-plugin/archive/v${SRIOV_DP_VER}.tar.gz
RUN mkdir -p sriov-dp && \
    tar xzf sriov-dp.tgz --strip-components=1 -C sriov-dp && \
    cd sriov-dp && \
    make && \
    cp build/sriovdp /bin

# Build vfioveth plugin
FROM busybox as vfioveth
RUN wget -O /bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
COPY cni/vfioveth /bin/vfioveth
RUN chmod +x /bin/vfioveth /bin/jq

# Final image
FROM centos/systemd
WORKDIR /tmp/cni/bin
COPY --from=multus /bin/multus-cni .
COPY --from=sriov-cni /bin/sriov .
COPY --from=vfioveth /bin/vfioveth .
COPY --from=vfioveth /bin/jq .
WORKDIR /usr/bin
COPY --from=sriov-dp /bin/sriovdp .
