#!/bin/bash

echo "Preparing the following SSD devices $1"
for i in "$@"; do {
  cmd="blkdiscard /dev/${i}"
  echo "Command \"$cmd\" started..";
  $cmd & pid=$!
  PID_LIST1+=" $pid";
} done

trap "kill $PID_LIST1" SIGINT
echo "Waiting for blkdiscard to complete";
wait $PID_LIST1
echo
echo "blkdiscard completed.";

