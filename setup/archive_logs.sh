#!/usr/bin/env bash

set -euo pipefail

#--- derive file name -----------------------------------------------------------
USER_NAME="$(id -un)"          # current login name (robust even in sudo)
DATE_STAMP="$(date +%Y-%m-%d)" # ISO date
ARCHIVE_NAME="${USER_NAME}-${DATE_STAMP}.tar.gz"

#--- locate journal directories -------------------------------------------------
JOURNAL_DIRS=( /var/log/journal /run/log/journal )

# Filter out any that don’t exist on this host
DIRS_TO_ARCHIVE=()
for d in "${JOURNAL_DIRS[@]}"; do
  [[ -d "$d" ]] && DIRS_TO_ARCHIVE+=("$d")
done

if [[ ${#DIRS_TO_ARCHIVE[@]} -eq 0 ]]; then
  echo "No systemd-journal directories found – nothing to archive." >&2
  exit 1
fi

#--- create compressed tarball --------------------------------------------------
# Needs root to read binary journal files; run with sudo if necessary.
tar -czf "$ARCHIVE_NAME" "${DIRS_TO_ARCHIVE[@]}"

echo "✓ Journal logs archived to: $ARCHIVE_NAME"

sudo mount 192.168.100.201:/store /mnt/shared
cp "$ARCHIVE_NAME" /mnt/shared/logs