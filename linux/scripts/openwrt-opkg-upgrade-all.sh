#!/bin/sh

opkg update

for line in $(opkg list-upgradable | awk 'BEGIN { FS=" " }; { print $1  }')
do
   opkg upgrade $line
done;