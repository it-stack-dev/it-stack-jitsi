#!/bin/bash
# entrypoint.sh — IT-Stack jitsi container entrypoint
set -euo pipefail

echo "Starting IT-Stack JITSI (Module 08)..."

# Source any environment overrides
if [ -f /opt/it-stack/jitsi/config.env ]; then
    # shellcheck source=/dev/null
    source /opt/it-stack/jitsi/config.env
fi

# Execute the upstream entrypoint or command
exec "$$@"
