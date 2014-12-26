#!/bin/bash

# You shouldn't need to call this unless you want to rebuild.
# Docker build switches can be added to arg 2, such as --no-cache=true

set -e

dir="$1"

if [ x"$dir" == x"" ]; then
  echo "Path needed"
  exit 1
fi

cd "$dir"

docker build $2 -t millerlogic/irccmd "irccmd" || exit 1

docker build $2 -t millerlogic/ludebot "ludebot" || exit 1
