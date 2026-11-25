#!/system/bin/sh
MODDIR=${0%/*}
CONFIG="$MODDIR/config.json"
USAGE_DB="$MODDIR/usage.db"
SMART_DB="$MODDIR/smart.db"   # satir: paket tier acilma   (tier: sleep|deep)
LOG="$MODDIR/hypersleep.log"

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
}

get_val() {
    local v
    v=$(sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"?([^\",}]*)\"?.*$/\1/p" "$CONFIG" 2>/dev/null | head -n 1 | tr -d ' \r')
    if [ -n "$v" ]; then echo "$v"; else echo "$2"; fi
}

list_apps() {
    sed -nE 's/^[[:space:]]*"([A-Za-z0-9_.]+)"[[:space:]]*:[[:space:]]*"(sleep|freeze|auto)".*/\1 \2/p' "$CONFIG" 2>/dev/null
}

get_mode() {
    list_apps | while read -r p m; do
        if [ "$p" = "$1" ]; then
            echo "$m"
            break
        fi
    done
}

get_top_app() {
    local r
    r=$(dumpsys activity activities 2>/dev/null | grep -m 1 -E "topResumedActivity|mResumedActivity" | sed -E 's/.*\{[^ ]+ [^ ]+ ([^/ ]+)\/.*/\1/')
    case "$r" in
        *" "*|*"="*|*"/"*) r="" ;;
    esac
    # Bazi ROM'larda activity satiri farkli; pencere odagina dus
    if [ -z "$r" ]; then
        r=$(dumpsys window 2>/dev/null | grep -m 1 -E "mCurrentFocus|mFocusedApp" | sed -E 's/.*\{[^ ]+ [^ ]+ ([^/ ]+)\/.*/\1/')
        case "$r" in
            *" "*|*"="*|*"/"*) r="" ;;
        esac
    fi
    echo "$r"
}

update_usage() {
    local pkg="$1"
    [ -z "$pkg" ] && return
    grep -v "^${pkg}=" "$USAGE_DB" > "${USAGE_DB}.tmp" 2>/dev/null
    echo "${pkg}=$(date +%s)" >> "${USAGE_DB}.tmp"
    mv "${USAGE_DB}.tmp" "$USAGE_DB"
}

get_last_used() {
    grep "^${1}=" "$USAGE_DB" 2>/dev/null | head -n 1 | cut -d'=' -f2
}

get_wakefulness() {
    dumpsys power 2>/dev/null | grep -m 1 "mWakefulness=" | cut -d'=' -f2 | tr -d '\r '
}

smart_line() {
    local l=""
    if [ -f "$SMART_DB" ]; then
        while read -r p t o; do
            if [ "$p" = "$1" ]; then l="$t $o"; break; fi
        done < "$SMART_DB"
    fi
    if [ -n "$l" ]; then echo "$l"; else echo "sleep 0"; fi
}

smart_set() {
    local tmp="$SMART_DB.tmp"
    : > "$tmp"
    if [ -f "$SMART_DB" ]; then
        while read -r p t o; do
            [ -z "$p" ] && continue
            [ "$p" != "$1" ] && echo "$p $t $o" >> "$tmp"
        done < "$SMART_DB"
    fi
    echo "$1 $2 $3" >> "$tmp"
    mv "$tmp" "$SMART_DB"
}

# Hafif uyku: bildirim gelir, arka plan isi kisitli
apply_light() {
    cmd appops set "$1" RUN_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$1" WAKE_LOCK allow 2>/dev/null
    cmd appops set "$1" RUN_ANY_IN_BACKGROUND ignore 2>/dev/null
    am set-standby-bucket "$1" rare 2>/dev/null
}

# Derin Dondur: arka plan tamamen kesilir, force-stop yapilir ama uygulama simgesi kilitlenmez (pm suspend YOK)
apply_deep() {
    pm unsuspend "$1" >/dev/null 2>&1
    cmd appops set "$1" RUN_IN_BACKGROUND ignore 2>/dev/null
    cmd appops set "$1" RUN_ANY_IN_BACKGROUND ignore 2>/dev/null
    cmd appops set "$1" WAKE_LOCK ignore 2>/dev/null
    am set-standby-bucket "$1" restricted 2>/dev/null
    am set-inactive "$1" true 2>/dev/null
    am force-stop "$1" 2>/dev/null
}

# Kullanim sirasinda kisitlari gevset
relax_for_use() {
    cmd appops set "$1" RUN_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$1" RUN_ANY_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$1" WAKE_LOCK allow 2>/dev/null
    am set-standby-bucket "$1" active 2>/dev/null
}

apply_sleep() {
    local pkg="$1"
    local mode="$2"
    local force="${3:-0}"
    [ "$mode" = "off" ] && return
    pm path "$pkg" >/dev/null 2>&1 || return

    # Ekran acikken on plandaki uygulamaya dokunma. Ekran kapaliyken (force=1)
    # on planda kalmis olsa bile uyut — kilitliyken kullanici uygulamayi gormuyor.
    if [ "$force" != "1" ] && [ "$(get_wakefulness)" = "Awake" ] && [ "$pkg" = "$(get_top_app)" ]; then
        return
    fi

    case "$mode" in
        freeze)
            log "dondur (derin): $pkg"
            apply_deep "$pkg"
            ;;
        auto)
            local line tier
            line=$(smart_line "$pkg")
            tier=${line%% *}
            if [ "$tier" = "deep" ]; then
                log "derin (auto): $pkg"
                apply_deep "$pkg"
            else
                log "uyut (auto): $pkg"
                apply_light "$pkg"
            fi
            ;;
        *)
            log "uyut (sleep): $pkg"
            apply_light "$pkg"
            ;;
    esac
}

run_screen_off() {
    list_apps | while read -r pkg mode; do
        [ -z "$pkg" ] && continue
        apply_sleep "$pkg" "$mode" 1
    done
}

run_inactivity() {
    local days hours mins total_sec s_days s_hours s_mins smart_sec now manual top_app wake
    days=$(get_val "inactivity_days" 1)
    hours=$(get_val "inactivity_hours" 0)
    mins=$(get_val "inactivity_minutes" 0)
    total_sec=$(( days * 86400 + hours * 3600 + mins * 60 ))
    [ "$total_sec" -lt 60 ] && total_sec=60

    # Oto mod icin ozel "Tekrar Derin'e Alma Suresi"
    s_days=$(get_val "smart_deep_days" 0)
    s_hours=$(get_val "smart_deep_hours" 0)
    s_mins=$(get_val "smart_deep_minutes" 15)
    smart_sec=$(( s_days * 86400 + s_hours * 3600 + s_mins * 60 ))
    [ "$smart_sec" -lt 60 ] && smart_sec=60

    manual=$(get_val "auto_sleep_unused" true)
    now=$(date +%s)
    top_app=$(get_top_app)
    wake=$(get_wakefulness)

    list_apps | while read -r pkg mode; do
        [ -z "$pkg" ] && continue
        # Ekranda aktif kullaniliyorsa sayaci sifirla ve dokunma
        if [ "$wake" = "Awake" ] && [ "$pkg" = "$top_app" ]; then
            update_usage "$pkg"
            continue
        fi

        last=$(get_last_used "$pkg")
        if [ -z "$last" ]; then
            update_usage "$pkg"
            continue
        fi
        idle=$(( now - last ))
        if [ "$mode" = "auto" ]; then
            line=$(smart_line "$pkg")
            tier=${line%% *}
            if [ "$tier" = "sleep" ] && [ "$idle" -ge "$smart_sec" ]; then
                smart_set "$pkg" deep 0
                log "oto-dusur: $pkg Uyku -> Derin (${idle}sn kullanilmadi, limit=${smart_sec}sn)"
                apply_deep "$pkg"
            fi
        elif [ "$manual" = "true" ] && [ "$idle" -ge "$total_sec" ]; then
            apply_sleep "$pkg" "$mode"
        fi
    done
}

on_open() {
    local pkg="$1" mode line tier opens thr
    [ -z "$pkg" ] && return
    mode=$(get_mode "$pkg")
    [ "$mode" = "auto" ] || return
    line=$(smart_line "$pkg")
    tier=${line%% *}
    opens=${line##* }
    [ "$tier" = "deep" ] || return
    thr=$(get_val "smart_open_threshold" 5)
    opens=$(( opens + 1 ))
    relax_for_use "$pkg"
    update_usage "$pkg"
    if [ "$opens" -ge "$thr" ]; then
        smart_set "$pkg" sleep 0
        log "oto-terfi: $pkg Derin -> Uyku (acilma=$opens)"
    else
        smart_set "$pkg" deep "$opens"
        log "acildi: $pkg (Derin, acilma=$opens/$thr)"
    fi
}

[ "${HS_TEST:-}" = "1" ] && return 0

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 5
done
sleep 15

touch "$USAGE_DB"
touch "$SMART_DB"
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 100000 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
log "servis basladi (v2.8)"

LAST_TOP=""
SCREEN_OFF_TRIGGERED=0
LAST_INACT_CHECK=0

while true; do
    CURRENT_TOP=$(get_top_app)
    SCREEN_STATE=$(get_wakefulness)
    NOW_TS=$(date +%s)

    if [ -n "$CURRENT_TOP" ] && [ "$SCREEN_STATE" = "Awake" ]; then
        update_usage "$CURRENT_TOP"
        if [ "$CURRENT_TOP" != "$LAST_TOP" ]; then
            on_open "$CURRENT_TOP"
        fi
    fi

    # Uygulamadan cikis yapildiginda cikis zamanini kaydet ve gecikme sonunda uyut
    if [ -n "$LAST_TOP" ] && [ "$LAST_TOP" != "$CURRENT_TOP" ]; then
        update_usage "$LAST_TOP"
        MODE=$(get_mode "$LAST_TOP")
        if [ -n "$MODE" ]; then
            E_DELAY=$(get_val exit_delay_sec 30)
            PKG_EXIT="$LAST_TOP"
            (
                sleep "$E_DELAY"
                if [ "$(get_top_app)" != "$PKG_EXIT" ]; then
                    apply_sleep "$PKG_EXIT" "$MODE"
                fi
            ) &
        fi
    fi

    # Hem ekran acikken hem ekran kapaliyken her 30 saniyede bir sure kontrolu yap
    if [ $((NOW_TS - LAST_INACT_CHECK)) -ge 30 ]; then
        LAST_INACT_CHECK=$NOW_TS
        run_inactivity
    fi

    if [ -n "$SCREEN_STATE" ] && [ "$SCREEN_STATE" != "Awake" ]; then
        if [ "$SCREEN_OFF_TRIGGERED" -eq 0 ]; then
            sleep "$(get_val screen_off_delay_sec 20)"
            RECHECK=$(get_wakefulness)
            if [ -n "$RECHECK" ] && [ "$RECHECK" != "Awake" ]; then
                log "ekran kapali -> liste uyutuluyor"
                run_screen_off
                SCREEN_OFF_TRIGGERED=1
            fi
        fi
        LAST_TOP="$CURRENT_TOP"
        sleep 10
        continue
    else
        SCREEN_OFF_TRIGGERED=0
    fi

    LAST_TOP="$CURRENT_TOP"
    sleep 5
done
