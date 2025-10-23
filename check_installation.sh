#!/bin/bash

echo "=== Logger System Health Check ==="
echo

echo "1. Checking Database Connection..."
# First check what's in the connection.php file
echo "  Checking connection.php content:"
grep "\$password\|\$username\|\$host\|\$dbname" connection.php | sed 's/^/    /'

# Test with PHP to get more detailed error information
php -r "
require './connection.php';
echo 'Host: ' . \$host . '\n';
echo 'Database: ' . \$dbname . '\n';
echo 'Username: ' . \$username . '\n';
echo 'Password length: ' . strlen(\$password) . '\n';
try {
    \$pdo = new PDO(\"mysql:host=\$host;dbname=\$dbname\", \$username, \$password);
    echo \"Connection successful\n\";
} catch (PDOException \$e) {
    echo \"Connection failed: \" . \$e->getMessage() . \"\n\";
}
" 2>&1 || echo "FAILED"

echo "2. Checking Cron Job..."
crontab -l | grep -q "log_fetcher" && echo "OK" || echo "NOT FOUND"

echo "3. Checking Cron Service..."
systemctl is-active --quiet cron && echo "OK" || echo "NOT RUNNING"

echo "4. Checking Log Directory..."
[ -d /var/log/logger_system ] && echo "OK" || echo "NOT FOUND"

echo "5. Checking Recent Cron Execution..."
if [ -f /var/log/logger_system/log_fetcher.log ]; then
    LAST_RUN=$(tail -n 5 /var/log/logger_system/log_fetcher.log | grep "Started" | tail -1)
    if [ -z "$LAST_RUN" ]; then
        echo "NO RECENT ACTIVITY"
    else
        echo "$LAST_RUN"
    fi
else
    echo "LOG FILE NOT FOUND"
fi

echo "6. Checking Database Records..."
mysql -u root -p -e "USE logger_db; 
    SELECT 
        (SELECT COUNT(*) FROM collectors) as collectors,
        (SELECT COUNT(*) FROM log_mirror) as logs,
        (SELECT COUNT(*) FROM parsed_logs) as parsed,
        (SELECT COUNT(*) FROM devices) as devices;" 2>/dev/null || echo "DATABASE CHECK FAILED"

echo
echo "=== Health Check Complete ==="