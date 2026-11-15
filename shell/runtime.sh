#!/usr/bin/env bash
# Build the exact runtime required by the imported-scene shell.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=0.8.0-exp.22
TAG="v$VERSION"
SRC="$DIR/cloned_repos/pleamar"
DEST="$DIR/bin/exp/pleamar-$VERSION"
if [ ! -x "$DEST" ]; then
    command -v cargo >/dev/null || { echo 'Install the Rust toolchain (cargo) first.' >&2; exit 1; }
    if [ ! -d "$SRC/.git" ]; then
        mkdir -p "$DIR/cloned_repos"
        git clone --depth 1 --branch "$TAG" https://github.com/k4ditano/pleamar "$SRC"
    fi
    if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
        echo "Runtime sources have local changes: $SRC" >&2
        exit 1
    fi
    git -C "$SRC" fetch origin tag "$TAG"
    git -C "$SRC" checkout --detach "$TAG"
    cargo build --release --locked --manifest-path "$SRC/Cargo.toml"
    mkdir -p "$DIR/bin/exp"
    cp "$SRC/target/release/pleamar" "$DEST.tmp"
    mv "$DEST.tmp" "$DEST"
fi
ln -sfn "pleamar-$VERSION" "$DIR/bin/exp/pleamar"
"$DIR/bin/exp/pleamar" --version
