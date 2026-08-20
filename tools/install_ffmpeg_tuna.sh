#!/bin/sh
set -eu

SOURCE_TEMPLATE="/home/xpg/chiplab/tools/ubuntu-focal-tuna.sources.list"
SYSTEM_SOURCE="/etc/apt/sources.list"
BACKUP_SOURCE="/etc/apt/sources.list.codex-backup"

if [ ! -r "$SOURCE_TEMPLATE" ]; then
    echo "Missing source template: $SOURCE_TEMPLATE" >&2
    exit 1
fi

if [ ! -e "$BACKUP_SOURCE" ]; then
    cp -a "$SYSTEM_SOURCE" "$BACKUP_SOURCE"
    echo "Original source saved as $BACKUP_SOURCE"
else
    echo "Keeping existing backup $BACKUP_SOURCE"
fi

install -m 0644 "$SOURCE_TEMPLATE" "$SYSTEM_SOURCE"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg

echo "Installed:"
ffmpeg -version | sed -n '1p'
echo "Restore command: cp '$BACKUP_SOURCE' '$SYSTEM_SOURCE' && apt-get update"
