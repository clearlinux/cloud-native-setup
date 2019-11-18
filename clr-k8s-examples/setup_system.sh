#!/usr/bin/env bash

set -o errexit
set -o nounset

# global vars
CLRK8S_OS=${CLRK8S_OS:-""}
CLR_VER=${CLRK8S_CLR_VER:-""}
HIGH_POD_COUNT=${HIGH_POD_COUNT:-""}

# set no proxy
ADD_NO_PROXY=".svc,10.0.0.0/8,192.168.0.0/16"
ADD_NO_PROXY+=",$(hostname -I | sed 's/[[:space:]]/,/g')"
if [[ -z "${RUNNER+x}" ]]; then RUNNER="${CLRK8S_RUNNER:-crio}"; fi

# update os version
function upate_os_version() {
	if [[ -n "${CLR_VER}" ]]; then
		sudo swupd repair -m "${CLR_VER}" --picky
		return
	fi
	sudo swupd update
}

# add depdencies such as k8s and crio
function add_os_deps() {
	sudo -E swupd bundle-add --quiet cloud-native-basic storage-utils
}

# permanently disable swap
function disable_swap() {
	swapcount=$(sudo grep '^/dev/\([0-9a-z]*\).*' /proc/swaps | wc -l)

	if [ "$swapcount" != "0" ]; then
		sudo systemctl mask "$(sed -n -e 's#^/dev/\([0-9a-z]*\).*#dev-\1.swap#p' /proc/swaps)" 2>/dev/null
	else
		echo "Swap not enabled"
	fi
}

# enable ip forwarding
function enable_ip_forwarding() {
	#Ensure 'default' and 'all' rp_filter setting of strict mode (1)
	#Inividual interfaces can still be configured to loose mode (2)
	#However, loose mode is not supported by Project Calico/felix, per
	#https://github.com/projectcalico/felix/issues/2082
	#Alternative is to set loose mode on and set Calico to run anyway as
	#described in the issue above.  However, loose mode is less secure
	#than strict. (See: https://github.com/dcos/dcos/pull/454#issuecomment-238408590)
	#This workaround can be removed when and if systemd reverts their
	#rp_filter settings back to 1 for 'default' and 'all'.
	sudo mkdir -p /etc/sysctl.d/
	cat <<EOT | sudo bash -c "cat > /etc/sysctl.d/60-k8s.conf"
net.ipv4.ip_forward=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
EOT
	sudo systemctl restart systemd-sysctl

}

# ensure the modules we need are preloaded
function setup_modules_load() {
	sudo mkdir -p /etc/modules-load.d/
	cat <<EOT | sudo bash -c "cat > /etc/modules-load.d/k8s.conf"
br_netfilter
vhost_vsock
overlay
EOT
}

# ensure hosts file setup
function setup_hosts() {
	# Make sure /etc/hosts file exists
	if [ ! -f /etc/hosts ]; then
		sudo touch /etc/hosts
	fi
	# add localhost to /etc/hosts file
	# shellcheck disable=SC2126
	hostcount=$(grep '127.0.0.1 localhost' /etc/hosts | wc -l)
	if [ "$hostcount" == "0" ]; then
		echo "127.0.0.1 localhost $(hostname)" | sudo bash -c "cat >> /etc/hosts"
	else
		echo "/etc/hosts already configured"
	fi
}

# write increased limits to specified file
function write_limits_conf() {
	cat <<EOT | sudo bash -c "cat > $1"
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=1048576
TimeoutStartSec=0
MemoryLimit=infinity
EOT
}

# update configuration to enable high pod counts
function config_high_pod_count() {
	# install bundle dependencies
	sudo -E swupd bundle-add --quiet jq bc

	# increase max inotify watchers
	cat <<EOT | sudo bash -c "cat > /etc/sysctl.conf"
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=1048576
EOT
	sudo sysctl -q -p

	# write configuration files
	sudo mkdir -p /etc/systemd/system/kubelet.service.d
	write_limits_conf "/etc/systemd/system/kubelet.service.d/limits.conf"
	if [ "$RUNNER" == "containerd" ]; then
		sudo mkdir -p /etc/systemd/system/containerd.service.d
		write_limits_conf "/etc/systemd/system/containerd.service.d/limits.conf"
	fi
	if [ "$RUNNER" == "crio" ]; then
		sudo mkdir -p /etc/systemd/system/crio.service.d
		write_limits_conf "/etc/systemd/system/crio.service.d/limits.conf"
	fi
}

# daemon reload
function daemon_reload() {
	sudo systemctl daemon-reload
}

# enable kubelet for $RUNNER
function enable_kubelet_runner() {
	# This will fail at this point, but puts it into a retry loop that
	# will therefore startup later once we have configured with kubeadm.
	sudo systemctl enable kubelet $RUNNER || true
}

# ensure that the system is ready without requiring a reboot
function ensure_system_ready() {
	sudo swapoff -a
	sudo systemctl restart systemd-modules-load.service
}

# add proxy if found
function setup_proxy() {
	set +o nounset
	if [[ ${http_proxy} ]] || [[ ${HTTP_PROXY} ]]; then
		echo "Setting up proxy stuff...."
		# Setup IP for users too
		sed_val=${ADD_NO_PROXY//\//\\/}
		[ -f /etc/environment ] && sudo sed -i "/no_proxy/I s/$/,${sed_val}/g" /etc/environment
		if [ -f /etc/profile.d/proxy.sh ]; then
			sudo sed -i "/no_proxy/I s/$/,${sed_val}/g" /etc/profile.d/proxy.sh
		else
			echo "Warning, failed to find /etc/profile.d/proxy.sh to edit no_proxy line"
		fi

		services=("${RUNNER}" 'kubelet')
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
}

# init for performing any pre tasks
function init() {
	echo ""
}

###
# main
##

if [[ -n "${CLRK8S_OS}" ]]; then
	# shellcheck disable=SC1090
	source "$(dirname "$0")/setup_system_${CLRK8S_OS}.sh"
fi

echo "Init..."
init
echo "Setting OS Version..."
upate_os_version
echo "Adding OS Dependencies..."
add_os_deps
echo "Disabling swap..."
disable_swap
echo "Enabling IP Forwarding..."
enable_ip_forwarding
echo "Setting up modules to load..."
setup_modules_load
echo "Setting up /etc/hosts..."
setup_hosts
if [[ -n "${HIGH_POD_COUNT}" ]]; then
	echo "Configure high pod count scaling..."
	config_high_pod_count
fi
echo "Reloading daemons..."
daemon_reload
echo "Enabling Kublet runner..."
enable_kubelet_runner
echo "Ensuring system is ready..."
ensure_system_ready
echo "Detecting and setting up proxy..."
setup_proxy

# We have potentially modified their env files, we need to restart the services.
# daemon reload
sudo systemctl daemon-reload
# restart runner
sudo systemctl restart $RUNNER || true
