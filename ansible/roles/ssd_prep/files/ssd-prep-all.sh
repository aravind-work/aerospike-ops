#!/bin/bash

sudo pkill -f blkdiscard
sudo pkill -f 'dd if'

echo "Preparing the following SSD devices $1"
for i in "$@"; do {
  cmd="sudo blkdiscard /dev/${i}"
  echo "Command \"$cmd\" started..";
  $cmd & pid=$!
  PID_LIST1+=" $pid";
} done

trap "sudo kill $PID_LIST1" SIGINT
echo "Waiting for blkdiscard to complete";
wait $PID_LIST1
echo
echo "sudo blkdiscard completed.";

for i in "$@"; do {
  cmd="sudo dd if=/dev/zero bs=32M of=/dev/${i}"
  echo "Command \"$cmd\" started..";
  $cmd & pid=$!
  PID_LIST2+=" $pid";
} done

trap "sudo kill $PID_LIST2" SIGINT
echo "Waiting for dd to complete";
wait $PID_LIST2
echo
echo "dd completed.";


