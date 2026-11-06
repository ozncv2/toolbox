#!/usr/bin/env bash
# Builds rsync from source: Ubuntu 26.04 ships a version with unpatched critical vulnerabilities.
# Usage: build-rsync.sh <source-dir> <output-dir>
set -euo pipefail

source=$1
out=$2
mkdir -p "$out"
[[ -x "$source/configure" ]] || exit 0

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends gcc make libc6-dev

build=$(mktemp -d)
cp -a "$source/." "$build/"
cd "$build"
./configure --quiet --prefix=/usr/local --disable-md2man --disable-locale \
    --disable-xxhash --disable-zstd --disable-lz4 --disable-openssl --disable-idn \
    --with-included-popt --with-included-zlib
make --silent -j"$(nproc)" rsync
strip rsync
install -m 0755 rsync "$out/rsync"
