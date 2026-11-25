#!/system/bin/sh
MODDIR=${0%/*}
CONFIG="$MODDIR/config.json"

sed -nE 's/^[[:space:]]*"([A-Za-z0-9_.]+)"[[:space:]]*:[[:space:]]*"(sleep|freeze|auto)".*/\1/p' "$CONFIG" | while read -r pkg; do
    [ -z "$pkg" ] && continue
    pm unsuspend "$pkg" >/dev/null 2>&1
    cmd appops set "$pkg" RUN_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$pkg" WAKE_LOCK allow 2>/dev/null
    am set-standby-bucket "$pkg" active 2>/dev/null
    am set-inactive "$pkg" false 2>/dev/null
done
