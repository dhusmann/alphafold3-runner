#!/bin/bash
# Script location handling - supports being called from repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/rclone_to_gdrive.sh"
