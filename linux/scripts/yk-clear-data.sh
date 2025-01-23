#!/bin/bash

if [[ $# < 2 ]]; then
    echo "Usage:";
    echo "      $0 <management_key> <pin> <start_datatag> <end_datatag>";
    echo;
    echo "<start_datatag> - default 0x5f0000";
    echo "  <end_datatag> - default 0x5fc100";
    echo;
    exit 1;
fi

mkey=$1;
pin=$2;

start_datatag=0x5f0000
end_datatag=0x5fc100

if [ -n "$3" ]; then
    start_datatag=$3
fi;

if [ -n "$4" ]; then
    end_datatag=$4
fi;

for n in $(seq $start_datatag $end_datatag); do
    hex=$(printf "0x%08x" "$n");
    echo "Clearing DataTag: $hex";
    ykman piv objects import -m $mkey -P $pin $hex /dev/null
done
