#!/system/bin/sh
last=""
count=0
while true; do
  sleep 20
  now=""
  for pid in $(ps | grep com.wesbos.homehq | grep -v " Z " | while read user pid rest; do echo $pid; done); do
    for task in /proc/$pid/task/*; do
      if grep -q "^State:.D" $task/status 2>/dev/null && grep -q _mali_osk_wait_queue_wait_event $task/wchan 2>/dev/null; then
        now="$now $task:$(grep "^voluntary_ctxt_switches" $task/status)"
      fi
    done
  done
  if [ -n "$now" ] && [ "$now" = "$last" ]; then
    count=$((count + 1))
  else
    count=0
  fi
  last="$now"
  if [ $count -ge 6 ]; then
    log -t skylit gpu-hang-reboot
    reboot
  fi
done
