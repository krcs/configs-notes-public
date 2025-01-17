#!/bin/sh

ls "$@" | awk '
  BEGIN {
    srand()
  };
  {
    files[NR-1] = $0
  };
  END { 
    print files[int(rand()*NR-1)]
  }
'
