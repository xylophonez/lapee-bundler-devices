#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd -P)
hyperbeam_dir=${HYPERBEAM_DIR:-"$repo_dir/../bulbasaur"}
device_dir=${BULBASAUR_DEVICE_DIR:-${LAPEE_DEVICE_DIR:-$repo_dir}}

if [ ! -d "$hyperbeam_dir" ]; then
    printf '%s\n' "Set HYPERBEAM_DIR to a HyperBEAM checkout." >&2
    printf '%s\n' "Tried: $hyperbeam_dir" >&2
    exit 1
fi

export BULBASAUR_DEVICE_DIR=$device_dir
export LAPEE_DEVICE_DIR=${LAPEE_DEVICE_DIR:-$device_dir}

(cd "$repo_dir/apps/hb_device" && rebar3 compile)

cd "$hyperbeam_dir"
exec rebar3 shell --apps hackney \
    --eval "file:script(\"$repo_dir/scripts/start-bulbasaur.erl\")."
