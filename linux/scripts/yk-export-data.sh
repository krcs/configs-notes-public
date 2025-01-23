#!/bin/bash

if [[ $# != 1 ]]; then
    echo "Usage:";
    echo "      $0 <output_file>";
    echo;
    exit 1;
fi

start_datatag=0x5f0000
end_datatag=0x5fc100

rm -f $1
for n in $(seq $start_datatag $end_datatag); do
    hex=$(printf "0x%08x" "$n");
    ykman piv objects export $hex - >> $1 2> /dev/null
    if [ $? -ne 0 ]; then
        break;
    fi;
done
