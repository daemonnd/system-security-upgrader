#!/bin/bash
set -Eeuo pipefail

rm -f /var/lib/system-security-upgrader/pending-ai-summary
echo "$SUDO_USER" >/var/lib/system-security-upgrader/pending-check
