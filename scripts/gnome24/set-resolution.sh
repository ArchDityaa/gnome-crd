#!/bin/bash
# Fallback: re-apply 1024x768 setelah desktop start (Mutter bisa reset mode).
WANT=1024x768
sleep 4
for try in 1 2 3 4 5 6; do
  for o in $(xrandr 2>/dev/null | grep " connected" | awk '{print $1}'); do
    xrandr --output "$o" --mode "$WANT" 2>/dev/null || true
  done
  xrandr 2>/dev/null | grep -qE " connected.*$WANT" && exit 0
  sleep 3
done
exit 0
