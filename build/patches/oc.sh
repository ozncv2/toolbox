#!/usr/bin/env bash
# Adapts oc 4.16 to the docker/docker v28 API. Its vulnerable dependencies cannot be
# upgraded otherwise. Runs in the root of the oc source tree.
set -euo pipefail

# AuthConfig moved from api/types to api/types/registry.
sed -i \
    -e 's#"github.com/docker/docker/api/types"#"github.com/docker/docker/api/types/registry"#' \
    -e 's#types\.AuthConfig#registry.AuthConfig#g' \
    pkg/cli/image/manifest/dockercredentials/credential_store_factory.go

# pkg/system no longer wraps mknod, so call the same syscall directly.
sed -i \
    -e 's#system\.Mknod(\(.*\), int(system\.Mkdev(hdr\.Devmajor, hdr\.Devminor)))#unix.Mknod(\1, int(unix.Mkdev(uint32(hdr.Devmajor), uint32(hdr.Devminor))))#' \
    -e '/docker\/pkg\/system"/d' \
    pkg/cli/image/archive/archive_unix.go
