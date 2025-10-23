#!/bin/bash

# Script to set up the cron job for log fetching

# Get the current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cron job entry
CRON_JOB="*/5 * * * * $SCRIPT_DIR/log_fetcher_cron.sh"

# Add to crontab
(crontab -l 2>/dev/null | grep -v "log_fetcher_cron.sh"; echo "$CRON_JOB") | crontab -

echo "Cron job has been set up to run every 5 minutes"
echo "Current crontab:"
crontab -l