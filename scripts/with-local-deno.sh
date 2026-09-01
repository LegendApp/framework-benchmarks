#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_directory")

local_deno_install="$repository_root/.toolchains/deno"
if [ -x "$local_deno_install/bin/deno" ]; then
  export DENO_INSTALL="$local_deno_install"
  export PATH="$DENO_INSTALL/bin:$PATH"
fi

exec "$@"
