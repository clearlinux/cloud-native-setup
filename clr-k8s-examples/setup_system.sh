#!/usr/bin/env bash

set -o errexit
set -o nounset

ADD_NO_PROXY="10.244.0.0/16,10.96.0.0/12"
ADD_NO_PROXY+=",$(hostname -I | sed 's/[[:space:]]/,/g')"

function clear_setup()
{
  #Install kubernetes and crio
  sudo -E swupd update
  sudo -E swupd bundle-add cloud-native-basic storage-utils shells
  echo "source <(kubectl completion bash)" >> $HOME/.bashrc
}

function ubuntu_setup()
{
  #Given the vagrant box we are using we need to really really do this hack for networking to work.
  # Check https://github.com/lavabit/robox/issues/35
  sudo sed -i "/nameservers/d" /etc/netplan/01-netcfg.yaml
  sudo sed -i "/addresses/d" /etc/netplan/01-netcfg.yaml
  sudo sed -i "s/DNS=.*/DNS=/g" /etc/systemd/resolved.conf
  sudo sed -i "s/DNSSEC=.*/DNSSEC=no/g" /etc/systemd/resolved.conf
  sudo netplan generate
  sudo netplan apply
  sudo systemctl restart systemd-networkd.service systemd-resolved.service

  # Now let us get on with life, shall we?
  kube_ver=$(curl -SsL https://storage.googleapis.com/kubernetes-release/release/stable.txt)
  KUBE_VERSION=${KUBE_VERSION:-${kube_ver#v}-*}
  CRIO_VERSION=${KUBE_VERSION%\.*}

  sudo -E apt update
  # Apparently doing this is messing with grub and other setting. For now go without.
  #TODO: Figure out how new boxes work and enable this.
  #sudo -E apt upgrade -y

  sudo apt install -y apt-transport-https curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo -E apt-key add -
  sudo bash -c 'cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF'
  sudo -E add-apt-repository -y ppa:projectatomic/ppa
  sudo -E apt update
  sudo -E apt install -y --allow-downgrades \
    kubelet=${KUBE_VERSION} \
    kubeadm=${KUBE_VERSION} \
    kubectl=${KUBE_VERSION}
  sudo -E apt install -y cri-o-${CRIO_VERSION}

  # Setup cgroup manager for crio
  sudo -E mkdir -p /etc/sysconfig
  sudo -E bash -c 'echo "CRIO_NETWORK_OPTIONS=\"--cgroup-manager cgroupfs\"" > /etc/sysconfig/crio'

  #Setup Kata
  ARCH=$(arch)
  sudo -E sh -c "echo 'deb http://download.opensuse.org/repositories/home:/katacontainers:/releases:/${ARCH}:/master/xUbuntu_$(lsb_release -rs)/ /' > /etc/apt/sources.list.d/kata-containers.list"
  curl -sL  http://download.opensuse.org/repositories/home:/katacontainers:/releases:/${ARCH}:/master/xUbuntu_$(lsb_release -rs)/Release.key | sudo apt-key add -
  sudo -E apt update
  sudo -E apt -y install kata-runtime kata-proxy kata-shim
}

# Find OS and run the right setup
OS=$(source /etc/os-release && echo $NAME)

case "$OS" in
  *"buntu"*)
    ubuntu_setup;;
  *"Clear"*)
    clear_setup;;
  *)
    echo "Untested OS. Not going forward" && exit 1;;
esac

#Permanently disable swap
swapcount=$(sudo grep '^/dev/\([0-9a-z]*\).*' /proc/swaps | wc -l)

if [ "$swapcount" != "0" ]; then
	sudo systemctl mask $(sed -n -e 's#^/dev/\([0-9a-z]*\).*#dev-\1.swap#p' /proc/swaps) 2>/dev/null
else
	echo "Swap not enabled"
fi

sudo mkdir -p /etc/sysctl.d/
cat <<EOT | sudo bash -c "cat > /etc/sysctl.d/60-k8s.conf"
net.ipv4.ip_forward=1
EOT
sudo systemctl restart systemd-sysctl

#Ensure the modules we need are preloaded
sudo mkdir -p /etc/modules-load.d/
cat <<EOT | sudo bash -c "cat > /etc/modules-load.d/k8s.conf"
br_netfilter
vhost_vsock
overlay
EOT

# Make sure /etc/hosts file exists
if [ ! -f /etc/hosts ]; then
  sudo touch /etc/hosts
fi
hostcount=$(grep '127.0.0.1 localhost' /etc/hosts | wc -l)
if [ "$hostcount" == "0" ]; then
	echo "127.0.0.1 localhost $(hostname)" | sudo bash -c "cat >> /etc/hosts"
else
	echo "/etc/hosts already configured"
fi

sudo systemctl daemon-reload
# This will fail at this point, but puts it into a retry loop that
# will therefore startup later once we have configured with kubeadm.
echo "The following kubelet command may complain... it is not an error"
sudo systemctl enable --now kubelet crio || true

sudo mkdir -p /usr/libexec/cni /opt/cni
[ ! -e /opt/cni/bin/cni ] && sudo ln -s /usr/libexec/cni /opt/cni/bin
#Ensure that the system is ready without requiring a reboot
sudo swapoff -a
sudo systemctl restart systemd-modules-load.service

set +o nounset
if [[ ${http_proxy} ]] || [[ ${HTTP_PROXY} ]]; then
	echo "Setting up proxy stuff...."
	# Setup IP for users too
	sed_val=${ADD_NO_PROXY//\//\\/}
	[ -f /etc/environment ] && sudo sed -i "/no_proxy/I s/$/,${sed_val}/g" /etc/environment
	if [ -f /etc/profile.d/proxy.sh ]; then
		sudo sed -i "/no_proxy/I s/\"$/,${sed_val}\"/g" /etc/profile.d/proxy.sh
	else
		echo "Warning, failed to find /etc/profile.d/proxy.sh to edit no_proxy line"
	fi

	services=('crio' 'kubelet' 'docker' 'containerd')
	for s in "${services[@]}"; do
		sudo mkdir -p "/etc/systemd/system/${s}.service.d/"
		cat <<EOF | sudo bash -c "cat > /etc/systemd/system/${s}.service.d/proxy.conf"
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="SOCKS_PROXY=${socks_proxy}"
Environment="NO_PROXY=${no_proxy},${ADD_NO_PROXY}"
EOF
	done
fi
set -o nounset

# We have potentially modified their env files, we need to restart the services.
sudo systemctl daemon-reload
sudo systemctl restart crio || true
sudo systemctl restart kubelet || true
