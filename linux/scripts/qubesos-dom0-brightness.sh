#!/bin/bash

if [ -z "$1" ] 
then
    echo "Usage:";
    echo "    sudo $0 [step]"
    exit 1;
fi;

max=4437;
current=$(cat /sys/class/backlight/intel_backlight/brightness);

new_value=$(( $current+$1 ));

if [ $new_value -le 0 ]
then
    new_value=0;
fi;

if [ $new_value -ge $max ]
then
   new_value=$max;
fi;

echo $new_value > /sys/class/backlight/intel_backlight/brightness
