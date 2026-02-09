#!/bin/bash
# ABOUTME: Mock script simulating mutagen CLI for unit tests.
# ABOUTME: Responds to all sync, forward, daemon, and version commands.

case "$1 $2" in
    "sync list")
        cat <<'JSON'
[{"identifier":"sync_test123","version":1,"creationTime":"2026-01-01T00:00:00Z","creatingVersion":"0.18.1","name":"test-session","alpha":{"protocol":"local","path":"/tmp/a","ignore":{},"symlink":{},"watch":{},"permissions":{},"compression":{},"connected":true,"scanned":true,"directories":10,"files":20,"totalFileSize":1000},"beta":{"protocol":"local","path":"/tmp/b","ignore":{},"symlink":{},"watch":{},"permissions":{},"compression":{},"connected":true,"scanned":true,"directories":10,"files":20,"totalFileSize":1000},"mode":"two-way-safe","ignore":{},"symlink":{},"watch":{},"permissions":{},"compression":{},"paused":false,"status":"watching","successfulCycles":5}]
JSON
        ;;
    "sync pause"|"sync resume"|"sync flush"|"sync reset"|"sync terminate")
        exit 0
        ;;
    "forward list")
        echo "[]"
        ;;
    "forward pause"|"forward resume"|"forward terminate")
        exit 0
        ;;
    "daemon start"|"daemon stop"|"daemon register"|"daemon unregister")
        exit 0
        ;;
    "version ")
        echo "0.18.1"
        ;;
    *)
        echo "0.18.1"
        ;;
esac
