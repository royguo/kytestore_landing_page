#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PID_FILE="$SCRIPT_DIR/server.pid"
DAEMON_PID_FILE="$SCRIPT_DIR/daemon.pid"
STOP_MARKER="$SCRIPT_DIR/.stop_marker"
LOG_FILE="$SCRIPT_DIR/server.log"
PYTHON_BIN="$SCRIPT_DIR/python3-local"

start_server() {
    if [ -f "$STOP_MARKER" ]; then
        rm -f "$STOP_MARKER"
    fi

    # Check if already running
    if [ -f "$SERVER_PID_FILE" ]; then
        OLD_PID=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            echo "[KyteStore] Server is already running (PID: $OLD_PID)"
            return 0
        fi
        rm -f "$SERVER_PID_FILE"
    fi

    cd "$SCRIPT_DIR"

    # Start Python server on port 80
    nohup "$PYTHON_BIN" server.py >> "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo $SERVER_PID > "$SERVER_PID_FILE"

    # Wait for server to start
    sleep 1
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "[KyteStore] Server started (PID: $SERVER_PID) on port 80"
    else
        echo "[KyteStore] Failed to start server"
        rm -f "$SERVER_PID_FILE"
        return 1
    fi

    # Start daemon monitor
    if [ -f "$DAEMON_PID_FILE" ]; then
        OLD_DAEMON_PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$OLD_DAEMON_PID" ] && kill -0 "$OLD_DAEMON_PID" 2>/dev/null; then
            echo "[KyteStore] Daemon already running (PID: $OLD_DAEMON_PID)"
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

            # Check server
            if [ -f "$SERVER_PID_FILE" ]; then
                CURRENT_PID=$(cat "$SERVER_PID_FILE" 2>/dev/null)
                if [ -n "$CURRENT_PID" ] && ! kill -0 "$CURRENT_PID" 2>/dev/null; then
                    echo "[KyteStore Daemon] Server died (PID: $CURRENT_PID), restarting..."
                    cd "$SCRIPT_DIR"
                    nohup "$PYTHON_BIN" server.py >> "$LOG_FILE" 2>&1 &
                    NEW_PID=$!
                    echo $NEW_PID > "$SERVER_PID_FILE"
                    echo "[KyteStore Daemon] Server restarted (PID: $NEW_PID)"
                fi
            fi

            sleep 3
        done
    ) &
    DAEMON_PID=$!
    echo $DAEMON_PID > "$DAEMON_PID_FILE"
    echo "[KyteStore] Daemon started (PID: $DAEMON_PID)"
}

stop_server() {
    touch "$STOP_MARKER"

    echo "[KyteStore] Stopping services..."

    if [ -f "$DAEMON_PID_FILE" ]; then
        DAEMON_PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
            kill "$DAEMON_PID" 2>/dev/null
            sleep 1
            kill -9 "$DAEMON_PID" 2>/dev/null
        fi
        rm -f "$DAEMON_PID_FILE"
    fi

    if [ -f "$SERVER_PID_FILE" ]; then
        SERVER_PID=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
            kill "$SERVER_PID" 2>/dev/null
            sleep 1
            kill -9 "$SERVER_PID" 2>/dev/null
        fi
        rm -f "$SERVER_PID_FILE"
    fi

    rm -f "$STOP_MARKER"
    echo "[KyteStore] Server stopped"
}

restart_server() {
    echo "[KyteStore] Restarting..."
    stop_server
    sleep 1
    start_server
}

status_server() {
    echo "[KyteStore] Status Check:"
    echo "---"

    if [ -f "$DAEMON_PID_FILE" ]; then
        DAEMON_PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
            echo "Daemon:  Running (PID: $DAEMON_PID)"
        else
            echo "Daemon:  Not running (stale PID file)"
        fi
    else
        echo "Daemon:  Not running"
    fi

    if [ -f "$SERVER_PID_FILE" ]; then
        SERVER_PID=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "Server:  Running (PID: $SERVER_PID)"
        else
            echo "Server:  Not running (stale PID file)"
        fi
    else
        echo "Server:  Not running"
    fi

    if [ -f "$STOP_MARKER" ]; then
        echo "Stop marker: Present (auto-restart disabled)"
    else
        echo "Stop marker: Not present (auto-restart enabled)"
    fi

    if [ -f "$LOG_FILE" ]; then
        echo "---"
        echo "Last 5 log lines:"
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    fi
}

case "$1" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status_server
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
