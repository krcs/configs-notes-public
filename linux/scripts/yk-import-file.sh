#!/bin/bash

if [[ $# != 4 ]]; then
    echo "Usage:";
    echo "      $0 <input_file> <max_data_size> <management_key> <pin>";
    echo;
    echo "<max_data_size>:";
    echo "   Yubikey NEO, Firmware 3.5.0 - 2034 bytes";
    echo "     Yubikey 4, Frimware 4.3.4 - 3046 bytes";
    echo " Yubikey 5 NFC, Firmware 5.4.3 - 3046 bytes";
    echo;
    exit 1;
fi

max_data_size=$2;
mkey=$3;
pin=$4;

start_datatag=5f0000

split -b $max_data_size -a 8 --hex-suffixes=$start_datatag $1 0x

for n in 0x*; do
    ykman piv objects import -m $mkey -P $pin $n $n
    if [ $? -eq 0 ]; then
        rm -f $n
    fi;
done
