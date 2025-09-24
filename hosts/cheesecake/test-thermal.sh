#!/usr/bin/env bash
# Quick thermal management test script

echo "=== Current thermal status ==="
for zone in /sys/class/thermal/thermal_zone*/temp; do
    temp=$(cat $zone)
    echo "$(basename $(dirname $zone)): $((temp/1000))°C"
done

echo -e "\n=== Thermald status ==="
systemctl status thermald --no-pager | grep -E "Active:|thermal-conf.xml"

echo -e "\n=== CPU frequency governor ==="
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

echo -e "\n=== Running stress test for 30 seconds ==="
echo "Watch temperatures - they should stabilize around 60-70°C with throttling"
stress --cpu 4 --timeout 30s &
STRESS_PID=$!

for i in {1..6}; do
    sleep 5
    echo -n "After ${i}0s: "
    cat /sys/class/thermal/thermal_zone*/temp | sort -rn | head -1 | awk '{printf "%.1f°C ", $1/1000}'
    echo -n "CPU MHz: "
    grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{print $4}'
done

wait $STRESS_PID
echo -e "\n=== Post-stress cooldown (10s) ==="
sleep 10
for zone in /sys/class/thermal/thermal_zone*/temp; do
    temp=$(cat $zone)
    echo "$(basename $(dirname $zone)): $((temp/1000))°C"
done