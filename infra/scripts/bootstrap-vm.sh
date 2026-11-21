#!/usr/bin/env bash
# One-time hardening of the Oracle VM (blueprint section 52, "The VM, step by step"). Run as the image's admin user:
#   ssh northgate 'sudo bash -s' < infra/scripts/bootstrap-vm.sh
# Safe to run again. Works on Ubuntu (apt) and Oracle Linux (dnf).
set -euo pipefail
AGE_VERSION=v1.3.2
AGE_ARM64_SHA256=6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4
admin="${SUDO_USER:-$(logname)}"

if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -yq unattended-upgrades fail2ban iptables-persistent git curl ca-certificates
  dpkg-reconfigure -f noninteractive unattended-upgrades
  if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
  # Oracle's Ubuntu images reject everything but SSH in iptables: open web ports above that reject rule (or append if none).
  for port in 80 443; do
    iptables -C INPUT -p tcp --dport "$port" -m state --state NEW -j ACCEPT 2>/dev/null && continue
    reject="$(iptables -L INPUT --line-numbers -n | awk '$2 == "REJECT" { print $1; exit }')"
    if [ -n "$reject" ]; then iptables -I INPUT "$reject" -p tcp --dport "$port" -m state --state NEW -j ACCEPT
    else iptables -A INPUT -p tcp --dport "$port" -m state --state NEW -j ACCEPT; fi
  done
  netfilter-persistent save
else
  dnf install -yq dnf-automatic fail2ban git curl
  systemctl enable --now dnf-automatic-install.timer
  if ! command -v docker >/dev/null; then
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    dnf install -yq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  fi
  firewall-cmd --permanent --add-service=http --add-service=https && firewall-cmd --reload
fi
systemctl enable --now docker fail2ban

# SSH: keys only, no root sign-in.
cat >/etc/ssh/sshd_config.d/10-northgate.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
systemctl reload ssh 2>/dev/null || systemctl reload sshd

cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
EOF
systemctl restart fail2ban

# age, for encrypting backups, checked against the release's published SHA-256.
if ! command -v age >/dev/null; then
  tmp="$(mktemp -d)"
  curl -fsSLo "$tmp/age.tgz" "https://github.com/FiloSottile/age/releases/download/$AGE_VERSION/age-$AGE_VERSION-linux-arm64.tar.gz"
  echo "$AGE_ARM64_SHA256  $tmp/age.tgz" | sha256sum -c -
  tar -xzf "$tmp/age.tgz" -C "$tmp" && install -m 755 "$tmp/age/age" /usr/local/bin/age && rm -rf "$tmp"
fi

# A non-root deploy user that runs the stack; it signs in with the same key as the admin user.
id deploy >/dev/null 2>&1 || useradd --create-home --shell /bin/bash deploy
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy "/home/$admin/.ssh/authorized_keys" /home/deploy/.ssh/authorized_keys
install -d -o deploy -g deploy /opt/northgate
[ -d /opt/northgate/.git ] || sudo -u deploy git clone -q https://github.com/FionaMich/northgate-dental.git /opt/northgate
install -m 644 -o deploy /dev/null /var/log/northgate-backup.log

cat >/etc/cron.d/northgate <<'EOF'
# Nightly encrypted backup at 02:00 UTC; certificate renewal every Monday at 03:30 UTC.
0 2 * * * deploy /opt/northgate/infra/scripts/backup.sh >> /var/log/northgate-backup.log 2>&1
30 3 * * 1 deploy cd /opt/northgate/infra && docker compose --profile tools run --rm certbot renew -q && docker compose exec -T waf nginx -s reload
EOF
# shellcheck source=/dev/null
echo "bootstrap done: $(. /etc/os-release; echo "$PRETTY_NAME"), docker $(docker --version | cut -d' ' -f3 | tr -d ,), age $(age --version)"
