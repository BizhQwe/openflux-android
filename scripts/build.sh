#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
all_targets=$(tr -d '\r' < scripts/targets.txt)
targets="${*:-$all_targets}"
if [ "$targets" = "--all" ]; then
    targets=$all_targets
fi
for target in $targets; do
    case " $(printf '%s' "$all_targets" | tr '\n' ' ') " in
        *" $target "*) ;;
        *) echo "Unsupported target: $target" >&2; exit 1 ;;
    esac
done
command -v sha256sum >/dev/null 2>&1 || { echo 'sha256sum is required.' >&2; exit 1; }
go=${GO:-go}
mkdir -p dist
for target in $targets; do
    os=${target%%-*}
    arch=${target#*-}
    arm=""
    [ "$arch" != armv7 ] || { arch=arm; arm=7; }
    suffix=""
    [ "$os" != windows ] || suffix=.exe
    binary="dist/openflux-$target$suffix"
    echo "Building $target -> $binary"
    GOOS="$os" GOARCH="$arch" GOARM="$arm" CGO_ENABLED=0 GOFLAGS=-buildvcs=false \
        "$go" build -C core -trimpath -ldflags='-s -w' -o "../$binary" .
    (cd dist && sha256sum "$(basename "$binary")") > "$binary.sha256"
    if [ "$os" = "linux" ] && { [ "$arch" = "amd64" ] || [ "$arch" = "arm64" ]; }; then
        opensub="dist/opensub-$target"
        echo "Building $opensub"
        GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 GOFLAGS=-buildvcs=false \
            "$go" build -C core -trimpath -ldflags='-s -w' -o "../$opensub" ./cmd/opensub
        (cd dist && sha256sum "$(basename "$opensub")") > "$opensub.sha256"
    fi
done
