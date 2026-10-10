#!/bin/sh
#
# Generates the placeholder skin into Resources/Skins/placeholder.
#
# The generator is a Swift script that draws frames with Core Graphics; this wrapper just runs it
# from the repository root, which is where the script expects to be.
set -eu

cd "$(dirname "$0")/.."
exec swift Scripts/make-placeholder-skin.swift "$@"
