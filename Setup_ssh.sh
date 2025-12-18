#!/bin/bash
cp Public_homelab_linux /home/root/.ssh/authorized_keys

sed -i 's/#PubkeyAuthentication no/PubkeyAuthentication yes/'  /etc/ssh/sshd_config
sed -i 's|#AuthorizedKeysFile      .ssh/authorized_keys .ssh/authorized_keys2|AuthorizedKeysFile      .ssh/authorized_keys .ssh/authorized_keys2|' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

rm /etc/apt/sources.list.d/ceph.sources
rm /etc/apt/sources.list.d/pve-enterprise.sources
cp proxmox.sources /etc/apt/sources.list.d/proxmox.sources