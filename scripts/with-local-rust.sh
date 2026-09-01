#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_directory")

local_cargo_home="$repository_root/.toolchains/cargo"
if [ -x "$local_cargo_home/bin/cargo" ]; then
  export CARGO_HOME="$local_cargo_home"
  export RUSTUP_HOME="$repository_root/.toolchains/rustup"
  export PATH="$CARGO_HOME/bin:$PATH"
fi

exec "$@"
