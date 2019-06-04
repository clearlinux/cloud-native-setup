#!/usr/bin/env bash

set -o errexit
set -o nounset

ADD_NO_PROXY="10.244.0.0/16,10.96.0.0/12"
ADD_NO_PROXY+=",$(hostname -I | sed 's/[[:space:]]/,/g')"

#Install kubernetes and crio
sudo -E swupd update
sudo -E swupd bundle-add cloud-native-basic storage-utils

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
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
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

	services=('crio' 'kubelet')
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
