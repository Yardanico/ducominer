#!/usr/bin/env sh
while true
do
  nim c -d:danger -r src/ducominer.nim
  sleep 1
done