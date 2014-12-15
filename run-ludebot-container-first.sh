#!/bin/bash

set -e

dir="$1"
containerName="$2"

if [ x"$dir" == x"" ]; then
  echo "Path needed"
  exit 1
fi

cd "$dir"

mkdir -p ludebot-state

if [ ! -f ludebot-state/ludebot.conf ]; then
  cp ludebot/ludebot.conf.example ludebot-state/ludebot.conf
  echo "Created a new $dir/ludebot-state/ludebot.conf" >&2
  echo "Please edit the conf file and then run this command again" >&2
  exit 222
fi

docker build -t millerlogic/irccmd "irccmd" || exit 1

docker build -t millerlogic/ludebot "ludebot" || exit 1

echo "Warning: about to write a clean state with blank data files..." >&2
sleep 3
echo "Running as firstrun..." >&2

chmod a+rw ludebot-state

./ludebot/run-ludebot-container.sh "." "$containerName" "first"
