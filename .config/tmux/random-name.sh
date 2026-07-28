#!/usr/bin/env bash
# Pick a random line from names.txt.
# Seed awk's srand() with $RANDOM so rapid calls within the same second still
# give different results (awk's default time-based seed has 1s resolution).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
awk -v seed="$RANDOM" 'BEGIN{srand(seed)}{a[NR]=$0}END{if(NR>0)print a[int(rand()*NR)+1]}' "$DIR/names.txt"
