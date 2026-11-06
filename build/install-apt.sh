#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Licences stay; documentation and other translations are not installed, now or by later layers.
cat >/etc/dpkg/dpkg.cfg.d/toolbox-slim <<'EOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/lintian/*
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/en*/*
path-include=/usr/share/locale/tr/*
EOF

# The base image deletes downloaded packages, which would defeat the build's cache mount.
mv /etc/apt/apt.conf.d/docker-clean /tmp/docker-clean

mapfile -t packages < <(grep -Ev '^[[:space:]]*(#|$)' /build/apt-packages.txt)
wanted=()
for package in "${packages[@]}"; do
    if [[ ",${TOOLBOX_EXCLUDE:-}," != *",$package,"* ]]; then
        wanted+=("$package")
    fi
done

apt-get update -qq
apt-get upgrade -y -qq --no-install-recommends
apt-get install -y -qq --no-install-recommends "${wanted[@]}"

printf 'en_US.UTF-8 UTF-8\ntr_TR.UTF-8 UTF-8\n' >/etc/locale.gen
locale-gen
rm -rf /usr/share/i18n/charmaps /usr/share/i18n/locales

mv /tmp/docker-clean /etc/apt/apt.conf.d/docker-clean
rm -rf /var/log/apt /var/log/dpkg.log /var/log/alternatives.log /var/cache/debconf/*-old /var/lib/dpkg/*-old
