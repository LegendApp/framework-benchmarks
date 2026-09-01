#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_directory")

local_flutter="$repository_root/.toolchains/flutter"
if [ -x "$local_flutter/bin/flutter" ]; then
  export PATH="$local_flutter/bin:$PATH"
fi

exec "$@"
