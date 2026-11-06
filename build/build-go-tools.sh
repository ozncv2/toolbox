#!/usr/bin/env bash
# Cross-compiles the tools in go-tools.lock from pinned commits with the stage's Go toolchain.
# It runs natively even when the target is emulated. go.sum checks every downloaded module.
# Usage: build-go-tools.sh <lockfile> <output-dir>
set -euo pipefail

lock=$1
out=$2
patches=$(dirname "$lock")/patches
mkdir -p "$out/bin" "$out/licenses"

# Without -buildvcs=false the binary records a pseudo-version such as v0.0.0-...+dirty, which
# scanners compare against fixed versions and wrongly report as old.
export CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOTOOLCHAIN=local GOWORK=off
export GOFLAGS='-mod=mod -buildvcs=false'

# Applied to every tool: these two modules are behind most of the findings and upgrade safely.
common_bumps=(golang.org/x/net@v0.62.0 golang.org/x/crypto@v0.58.0)

build() {
    local name=$1 version=$2 commit=$3 repo=$4 subdir=$5 package=$6 bumps=$7 tags=$8 ldflags=${9:-}
    local binary=$name

    # "version:binary" names a command that differs from the tool's name.
    if [[ "$version" == *:* ]]; then
        binary=${version##*:}
        version=${version%%:*}
    fi
    ldflags=${ldflags//\{version\}/$version}
    ldflags=${ldflags//\{commit\}/$commit}
    [[ "$tags" == - ]] && tags=

    # An entry with "=" is a go.mod replace, for a module the upgrades would otherwise move too far.
    local source entry upgrades=("${common_bumps[@]}") replaces=()
    if [[ "$bumps" != - ]]; then
        IFS=, read -ra extra <<<"$bumps"
        for entry in "${extra[@]}"; do
            if [[ "$entry" == *=* ]]; then
                replaces+=("$entry")
            else
                upgrades+=("$entry")
            fi
        done
    fi

    source=$(mktemp -d)
    git -C "$source" init -q
    git -C "$source" fetch -q --depth 1 "$repo" "$commit"
    git -C "$source" checkout -q FETCH_HEAD

    echo "building $name $version"
    (
        cd "$source"
        if [[ -f "$patches/$name.sh" ]]; then
            bash "$patches/$name.sh"
        fi
        cd "$subdir"
        go get "${upgrades[@]}"
        for entry in "${replaces[@]}"; do
            go mod edit -replace "$entry"
        done
        go build -trimpath -tags "$tags" -ldflags "-s -w $ldflags" -o "$out/bin/$binary" "$package"
    )

    mkdir -p "$out/licenses/$name"
    find "$source" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'COPYING*' \) \
        -exec cp {} "$out/licenses/$name/" \;
    rm -rf "$source"
}

excluded=",${TOOLBOX_EXCLUDE:-},"
while read -r kind name version commit repo subdir package bumps tags ldflags; do
    [[ -z "${kind:-}" || "$kind" == \#* ]] && continue
    [[ "$excluded" == *",$name,"* ]] && continue
    build "$name" "$version" "$commit" "$repo" "$subdir" "$package" "$bumps" "$tags" "${ldflags:-}"
done <"$lock"
