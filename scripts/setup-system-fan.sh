#!/bin/bash
HWMON="/sys/class/hwmon"
NCT=""
for h in $HWMON/hwmon*; do
    [ "$(cat $h/name 2>/dev/null)" = "nct6798" ] && NCT="$h" && break
done
[ -z "$NCT" ] && echo "nct6798 not found" && exit 1

# PECI reads ~12C lower than real CPU temp
# 55C PECI ≈ 67C real, 58C PECI ≈ 70C real
for pwm in 1 2 5; do
    echo 5 > "$NCT/pwm${pwm}_enable"
    echo 30000 > "$NCT/pwm${pwm}_auto_point1_temp"
    echo 51    > "$NCT/pwm${pwm}_auto_point1_pwm"
    echo 40000 > "$NCT/pwm${pwm}_auto_point2_temp"
    echo 64    > "$NCT/pwm${pwm}_auto_point2_pwm"
    echo 48000 > "$NCT/pwm${pwm}_auto_point3_temp"
    echo 128   > "$NCT/pwm${pwm}_auto_point3_pwm"
    echo 55000 > "$NCT/pwm${pwm}_auto_point4_temp"
    echo 230   > "$NCT/pwm${pwm}_auto_point4_pwm"
    echo 58000 > "$NCT/pwm${pwm}_auto_point5_temp"
    echo 255   > "$NCT/pwm${pwm}_auto_point5_pwm"
done
echo "Fan curve applied (PECI adjusted): 20%@30C -> 25%@40C -> 50%@48C -> 90%@55C -> 100%@58C"
echo "(Real CPU temps: quiet to ~60C, 50% at 60C, 90% at 67C, full blast 70C+)"
