#!/bin/sh
#
# Packs every skin under Resources/Skins into a sprite sheet with GIF previews.
#
# Pass skin names to pack only those, e.g. `Scripts/pack-skins.sh placeholder`.
set -eu

cd "$(dirname "$0")/.."
exec swift run SkinPacker "$@"
