#!/bin/bash
# First boot of the Northgate VM (rendered by Terraform). Clones the public repository and runs the hardening script.
set -euxo pipefail
exec > >(tee -a /var/log/northgate-cloud-init.log) 2>&1
dnf install -yq git
git clone -q ${repository} /root/northgate
ADMIN_USER=opc bash /root/northgate/infra/scripts/bootstrap-vm.sh
rm -rf /root/northgate
