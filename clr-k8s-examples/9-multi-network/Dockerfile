# Build multus plugin
FROM golang:1.10 AS multus
RUN git clone -q --depth 1 https://github.com/intel/multus-cni.git /go/src/github.com/intel/multus-cni
WORKDIR /go/src/github.com/intel/multus-cni
RUN ./build

# Build sriov plugin
FROM golang:1.10 AS sriov-cni
RUN git clone -q -b dev/k8s-deviceid-model https://github.com/Intel-Corp/sriov-cni.git /go/src/github.com/intel-corp/sriov-cni
WORKDIR /go/src/github.com/intel-corp/sriov-cni
RUN ./build

# Build sriov device plugin
FROM golang:1.10 AS sriov-dp
RUN git clone -q https://github.com/intel/sriov-network-device-plugin.git /go/src/github.com/intel/sriov-network-device-plugin
WORKDIR /go/src/github.com/intel/sriov-network-device-plugin
RUN make

# Build vfioveth plugin
FROM busybox as vfioveth
RUN wget -O /bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
COPY cni/vfioveth /bin/vfioveth
RUN chmod +x /bin/vfioveth /bin/jq

# Final image
FROM centos/systemd
WORKDIR /tmp/cni/bin
COPY --from=multus /go/src/github.com/intel/multus-cni/bin/multus .
COPY --from=sriov-cni /go/src/github.com/intel-corp/sriov-cni/bin/sriov .
COPY --from=vfioveth /bin/vfioveth .
COPY --from=vfioveth /bin/jq .
WORKDIR /usr/bin
COPY --from=sriov-dp /go/src/github.com/intel/sriov-network-device-plugin/build/sriovdp .
