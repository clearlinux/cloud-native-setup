# Detailed Vagrant installation steps
## Install vagrant on Ubuntu

On Ubuntu Bionic, run these commands
Install dependencies and prepare system
```bash
sudo apt-get update
sudo apt-get install gcc make
sudo apt-get install qemu qemu-kvm libvirt-bin ebtables dnsmasq-base virt-top  libguestfs-tools virtinst bridge-utils
sudo apt-get install libxslt-dev libxml2-dev libvirt-dev zlib1g-dev ruby-dev
sudo modprobe vhost_net
sudo lsmod | grep vhost
echo "vhost_net" | sudo tee -a /etc/modules
```
Download the latest Debian package from https://www.vagrantup.com/downloads.html and install it followed by vagrant-libvirt
```bash
sudo dpkg -i vagrant_${VER}_x86_64.deb
sudo vagrant plugin install vagrant-libvirt
```
Run vagrant
```bash
sudo vagrant up --provider=libvirt
```

Note, vagrant installation steps were derived from:
* https://computingforgeeks.com/install-kvm-centos-rhel-ubuntu-debian-sles-arch/
* https://computingforgeeks.com/using-vagrant-with-libvirt-on-linux/
* https://computingforgeeks.com/install-latest-vagrant-on-ubuntu-18-04-debian-9-kali-linux/
* https://github.com/vagrant-libvirt/vagrant-libvirt/blob/master/README.md

## Install vagrant on Clear Linux

On Clear Linux, run these commands
```bash
sudo wget https://github.com/AntonioMeireles/ClearLinux-packer/blob/master/extras/clearlinux/setup/libvirtd.sh
./libvirtd.sh
sudo wget https://raw.githubusercontent.com/AntonioMeireles/ClearLinux-packer/master/extras/clearlinux/setup/vagrant.sh
./vagrant.sh
```
Check if vagrant is installed successfully
```bash
vagrant --version
```
Run vagrant
```bash
vagrant up --provider=libvirt
```
