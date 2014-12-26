#!/bin/bash

set -e

if [ x"$1" == x"" ]; then
  echo "Path needed"
  exit 1
fi

dir=$(readlink -f "$1")
containerName="$2"

if [ x"$containerName" == x"" ]; then
  containerName=ludebot
fi

cd "$dir"

WHATRUN="$3"
if [ x"$WHATRUN" == x"" ]; then
  WHATRUN="next" # Note: don't depend on this.
fi

docker run \
  --name "$containerName" \
  -e "LUDEBOT_RUN=$WHATRUN" \
  -v $dir/ludebot-state:/ludebot-state \
  millerlogic/ludebot
