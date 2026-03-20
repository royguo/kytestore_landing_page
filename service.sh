#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PID_FILE="$SCRIPT_DIR/server.pid"
DAEMON_PID_FILE="$SCRIPT_DIR/daemon.pid"
STOP_MARKER="$SCRIPT_DIR/.stop_marker"
LOG_FILE="$SCRIPT_DIR/server.log"
PYTHON_BIN="$SCRIPT_DIR/python3-local"
SYSTEMD_UNIT="/etc/systemd/system/kytestore-backend.service"

systemd_backend_installed() {
    [ -f "$SYSTEMD_UNIT" ]
}

caddy_start() {
    if systemctl is-enabled caddy >/dev/null 2>&1 || systemctl cat caddy >/dev/null 2>&1; then
        systemctl start caddy 2>/dev/null && echo "[KyteStore] Caddy started (systemd)" && return 0
    fi
    echo "[KyteStore] Warning: caddy service not found; install Caddy or use: $0 start standalone"
    return 1
}

caddy_stop() {
    systemctl stop caddy 2>/dev/null && echo "[KyteStore] Caddy stopped" || true
}

backend_stop_systemd() {
    systemd_backend_installed || return 0
    systemctl stop kytestore-backend 2>/dev/null && echo "[KyteStore] kytestore-backend stopped" || true
}

backend_start_systemd() {
    if ! systemd_backend_installed; then
        return 1
    fi
    systemctl start kytestore-backend 2>/dev/null || return 1
    echo "[KyteStore] Python HTTP via systemd unit kytestore-backend"
    return 0
}

# Nohup-based watchdog + Python (standalone or fallback when no systemd unit).
stop_legacy_backend() {
    if [ -f "$DAEMON_PID_FILE" ]; then
        local daemon_pid
        daemon_pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid" 2>/dev/null
            sleep 1
            kill -9 "$daemon_pid" 2>/dev/null
        fi
        rm -f "$DAEMON_PID_FILE"
    fi

    if [ -f "$SERVER_PID_FILE" ]; then
        local server_pid
        server_pid=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
            kill "$server_pid" 2>/dev/null
            sleep 1
            kill -9 "$server_pid" 2>/dev/null
        fi
        rm -f "$SERVER_PID_FILE"
    fi
    rm -f "$STOP_MARKER"
}

wait_for_backend() {
    local port="$1"
    local i=0
    while [ "$i" -lt 50 ]; do
        if ss -tln 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
            return 0
        fi
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}

# Args: RUN_BIND RUN_PORT (exported into Python)
start_python_with_daemon() {
    local run_bind="$1"
    local run_port="$2"

    if [ -f "$STOP_MARKER" ]; then
        rm -f "$STOP_MARKER"
    fi

    if [ -f "$SERVER_PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            echo "[KyteStore] Python HTTP is already running (PID: $old_pid)"
            return 0
        fi
        rm -f "$SERVER_PID_FILE"
    fi

    cd "$SCRIPT_DIR" || return 1

    nohup env KYTESTORE_BIND="$run_bind" KYTESTORE_PORT="$run_port" \
        "$PYTHON_BIN" server.py >>"$LOG_FILE" 2>&1 &
    local server_pid=$!
    echo "$server_pid" >"$SERVER_PID_FILE"

    sleep 1
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "[KyteStore] Failed to start Python HTTP server"
        rm -f "$SERVER_PID_FILE"
        return 1
    fi
    echo "[KyteStore] Python HTTP started (PID: $server_pid) on $run_bind:$run_port"

    if [ -f "$DAEMON_PID_FILE" ]; then
        local old_d
        old_d=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$old_d" ] && kill -0 "$old_d" 2>/dev/null; then
            echo "[KyteStore] Watchdog already running (PID: $old_d)"
            return 0
        fi
        rm -f "$DAEMON_PID_FILE"
    fi

    (
        while true; do
            if [ -f "$STOP_MARKER" ]; then
                echo "[KyteStore Daemon] Stop marker detected, exiting..."
                exit 0
            fi

            if [ -f "$SERVER_PID_FILE" ]; then
                local cur
                cur=$(cat "$SERVER_PID_FILE" 2>/dev/null)
                if [ -n "$cur" ] && ! kill -0 "$cur" 2>/dev/null; then
                    echo "[KyteStore Daemon] Server died (PID: $cur), restarting..."
                    cd "$SCRIPT_DIR" || exit 1
                    nohup env KYTESTORE_BIND="$run_bind" KYTESTORE_PORT="$run_port" \
                        "$PYTHON_BIN" server.py >>"$LOG_FILE" 2>&1 &
                    local new_pid=$!
                    echo "$new_pid" >"$SERVER_PID_FILE"
                    echo "[KyteStore Daemon] Server restarted (PID: $new_pid)"
                fi
            fi
            sleep 3
        done
    ) &
    local daemon_pid=$!
    echo "$daemon_pid" >"$DAEMON_PID_FILE"
    echo "[KyteStore] Watchdog started (PID: $daemon_pid)"
}

start_stack() {
    local mode="${1:-caddy}"

    if [ "$mode" = "standalone" ]; then
        backend_stop_systemd
        caddy_stop
        stop_legacy_backend
        echo "[KyteStore] Mode: standalone (Python on :80, Caddy off)"
        start_python_with_daemon "0.0.0.0" "80" || return 1
        return 0
    fi

    echo "[KyteStore] Mode: caddy (Python on 127.0.0.1:9080, Caddy on 80/443)"

    stop_legacy_backend

    if systemd_backend_installed; then
        if ! backend_start_systemd; then
            echo "[KyteStore] Failed to start kytestore-backend"
            return 1
        fi
    else
        start_python_with_daemon "127.0.0.1" "9080" || return 1
    fi

    if ! wait_for_backend "9080"; then
        echo "[KyteStore] Warning: backend port 9080 not listening yet"
    fi
    caddy_start || true
}

stop_stack() {
    touch "$STOP_MARKER"
    echo "[KyteStore] Stopping services..."

    caddy_stop
    backend_stop_systemd

    if [ -f "$DAEMON_PID_FILE" ]; then
        local daemon_pid
        daemon_pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid" 2>/dev/null
            sleep 1
            kill -9 "$daemon_pid" 2>/dev/null
        fi
        rm -f "$DAEMON_PID_FILE"
    fi

    if [ -f "$SERVER_PID_FILE" ]; then
        local server_pid
        server_pid=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
            kill "$server_pid" 2>/dev/null
            sleep 1
            kill -9 "$server_pid" 2>/dev/null
        fi
        rm -f "$SERVER_PID_FILE"
    fi

    rm -f "$STOP_MARKER"
    echo "[KyteStore] All services stopped"
}

status_stack() {
    echo "[KyteStore] Status:"
    echo "---"

    if systemd_backend_installed; then
        if systemctl is-active --quiet kytestore-backend 2>/dev/null; then
            echo "Backend: active (systemd kytestore-backend)"
        else
            echo "Backend: inactive (systemd kytestore-backend)"
        fi
    else
        echo "Backend: (no kytestore-backend.service — using legacy mode if started)"
    fi

    if systemctl cat caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy 2>/dev/null; then
            echo "Caddy:   active (systemd)"
        else
            echo "Caddy:   inactive"
        fi
    else
        echo "Caddy:   not installed"
    fi

    if [ -f "$DAEMON_PID_FILE" ]; then
        local dpid
        dpid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
            echo "Watchdog: Running (PID: $dpid) [legacy]"
        else
            echo "Watchdog: Not running (stale PID file)"
        fi
    else
        echo "Watchdog: Not running [use systemd backend when installed]"
    fi

    if [ -f "$SERVER_PID_FILE" ]; then
        local spid
        spid=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
            echo "Python:  Running (PID: $spid) [legacy] — see server.log for bind"
        else
            echo "Python:  Not running (stale PID file)"
        fi
    else
        if systemd_backend_installed && systemctl is-active --quiet kytestore-backend 2>/dev/null; then
            echo "Python:  managed by systemd (see: systemctl status kytestore-backend)"
        else
            echo "Python:  Not running"
        fi
    fi

    echo "---"
    ss -tlnp 2>/dev/null | grep -E '(:80|:443|:9080)\b' || true

    if [ -f "$LOG_FILE" ]; then
        echo "---"
        echo "Last 5 log lines:"
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    fi
}

case "$1" in
    start)
        if [ "${2:-}" = "standalone" ]; then
            start_stack standalone
        else
            start_stack caddy
        fi
        ;;
    stop)
        stop_stack
        ;;
    restart)
        echo "[KyteStore] Restarting..."
        stop_stack
        sleep 1
        if [ "${2:-}" = "standalone" ]; then
            start_stack standalone
        else
            start_stack caddy
        fi
        ;;
    status)
        status_stack
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status} [standalone]"
        echo ""
        echo "  start          Backend (systemd kytestore-backend if installed) + Caddy"
        echo "  start standalone  Python on :80 only; stops systemd backend + Caddy"
        echo "  stop           Stop Caddy, kytestore-backend, legacy Python/watchdog"
        exit 1
        ;;
esac

exit 0
