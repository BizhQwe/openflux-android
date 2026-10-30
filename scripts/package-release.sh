#!/bin/sh
# Build and verify the complete release set; --skip-build checks existing assets.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
release_dir=dist
skip_build=0
directory_set=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-build) skip_build=1 ;;
        -h|--help)
            echo 'Usage: sh scripts/package-release.sh [--skip-build] [release-directory]'
            echo 'Builds all targets by default. --skip-build verifies previously built binaries.'
            exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            [ "$directory_set" -eq 0 ] || { echo 'Only one release directory is allowed.' >&2; exit 1; }
            release_dir=$1
            directory_set=1 ;;
    esac
    shift
done

command -v sha256sum >/dev/null 2>&1 || { echo 'sha256sum is required.' >&2; exit 1; }
if [ "$skip_build" -eq 0 ]; then
    sh scripts/build.sh --all
    mkdir -p "$release_dir"
    input_dir=dist
else
    input_dir=$release_dir
fi
if [ ! -d "$release_dir" ]; then
    echo "Release directory not found: $release_dir" >&2
    exit 1
fi
input_dir=$(CDPATH= cd -- "$input_dir" && pwd)
release_dir=$(CDPATH= cd -- "$release_dir" && pwd)
targets=$(tr -d '\r' < scripts/targets.txt)

checksums=""
for target in $targets; do
    suffix=''
    case "$target" in windows-*) suffix='.exe' ;; esac
    asset="openflux-$target$suffix"
    if [ ! -s "$input_dir/$asset" ] || [ ! -s "$input_dir/$asset.sha256" ]; then
        echo "Missing binary or SHA-256: $asset" >&2
        exit 1
    fi
    expected_hash=''
    expected_file=''
    read -r expected_hash expected_file < "$input_dir/$asset.sha256" || [ -n "$expected_hash" ]
    (cd "$input_dir" && printf '%s  %s\n' "$expected_hash" "$asset" | sha256sum --check --status) || {
        echo "Binary SHA-256 mismatch: $asset" >&2
        exit 1
    }
    checksums="${checksums}${expected_hash}  ${asset}
"
    if [ -f "$input_dir/opensub-$target" ]; then
        sub_asset="opensub-$target"
        read -r sub_hash sub_file < "$input_dir/$sub_asset.sha256" || [ -n "$sub_hash" ]
        (cd "$input_dir" && printf '%s  %s\n' "$sub_hash" "$sub_asset" | sha256sum --check --status) || {
            echo "Binary SHA-256 mismatch: $sub_asset" >&2
            exit 1
        }
        checksums="${checksums}${sub_hash}  ${sub_asset}
"
    fi
done

if [ "$input_dir" != "$release_dir" ]; then
    for target in $targets; do
        suffix=''
        case "$target" in windows-*) suffix='.exe' ;; esac
        asset="openflux-$target$suffix"
        cp "$input_dir/$asset" "$release_dir/$asset"
        cp "$input_dir/$asset.sha256" "$release_dir/$asset.sha256"
        if [ -f "$input_dir/opensub-$target" ]; then
            cp "$input_dir/opensub-$target" "$release_dir/opensub-$target"
            cp "$input_dir/opensub-$target.sha256" "$release_dir/opensub-$target.sha256"
        fi
    done
fi
printf '%s' "$checksums" > "$release_dir/SHA256SUMS.txt"
echo "Release ready: individual SHA-256 files and SHA256SUMS.txt in $release_dir."
