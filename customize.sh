#!/system/bin/sh
ui_print "*********************************************"
ui_print "  HyperSleep Smart Deep Sleep v2.8 (WebUI)"
ui_print "  TR / EN arayuz destegi"
ui_print "*********************************************"

OLD="/data/adb/modules/hypersleep"
if [ -f "$OLD/config.json" ]; then
    cp -af "$OLD/config.json" "$MODPATH/config.json"
fi
if [ -f "$OLD/usage.db" ]; then
    cp -af "$OLD/usage.db" "$MODPATH/usage.db"
fi
if [ -f "$OLD/smart.db" ]; then
    cp -af "$OLD/smart.db" "$MODPATH/smart.db"
fi

# Eski surumden kalan pm suspend kilitlerini kaldir
if [ -f "$MODPATH/config.json" ]; then
    sed -nE 's/^[[:space:]]*"([A-Za-z0-9_.]+)"[[:space:]]*:[[:space:]]*"(sleep|freeze|auto)".*/\1/p' "$MODPATH/config.json" | while read -r pkg; do
        [ -z "$pkg" ] && continue
        pm unsuspend "$pkg" >/dev/null 2>&1
    done
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
ui_print "- Kurulum tamamlandi!"
