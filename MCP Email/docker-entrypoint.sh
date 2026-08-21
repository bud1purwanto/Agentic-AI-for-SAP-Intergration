#!/bin/sh
set -e

# Start stunnel in background
if command -v stunnel4 >/dev/null 2>&1; then
    stunnel4 /etc/stunnel/stunnel.conf
elif command -v stunnel >/dev/null 2>&1; then
    stunnel /etc/stunnel/stunnel.conf
fi

# Execute main process (e.g. node dist/index.js or testConnection.js)
exec "$@"
