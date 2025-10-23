#!/bin/bash

# Set the working directory to the directory where this script is located
cd "$(dirname "$0")"

# Set environment variables
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create log directory if it doesn't exist
mkdir -p /var/log/logger_system

# Log file paths
LOG_FILE="/var/log/logger_system/log_fetcher.log"
ERROR_FILE="/var/log/logger_system/log_fetcher_error.log"

# Add timestamp to log
echo "=== Log Fetcher Started at $(date) ===" >> $LOG_FILE

# Run the PHP script and capture both output and errors
php /var/www/html/new-logger-backend--v1/log_fetcher.php >> $LOG_FILE 2>> $ERROR_FILE

# Check exit status
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Log fetcher completed successfully at $(date)" >> $LOG_FILE
else
    echo "Log fetcher failed with exit code $EXIT_CODE at $(date)" >> $ERROR_FILE
fi

echo "=== Log Fetcher Ended at $(date) ===" >> $LOG_FILE
echo "" >> $LOG_FILE