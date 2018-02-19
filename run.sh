#!/bin/bash
set -e

export RANCHER_IP=$(curl -s http://rancher-metadata.rancher.internal/latest/self/container/primary_ip)

stop() { 
  echo "Shutting down server..."
  echo "Sending SIGTERM to $child..."

  if kill -0 $child > /dev/null
  then
    echo "$child is running"
  else
    echo "$child is already dead!?"
  fi

  kill -TERM $child
  wait $child
}

trap stop TERM

#/app/_build/dev/rel/samantha/bin/samantha foreground &
elixir --name samantha@${RANCHER_IP} --cookie ${COOKIE} -S mix run --no-halt &

child=$!
echo "Waiting on PID $child..."

wait "$child"