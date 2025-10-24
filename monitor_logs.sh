#!/bin/bash

# Real-time Log Monitoring Script
# Shows live updates of incoming logs

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DB_NAME="syslog_db"
MYSQL_PASSWORD=""

# Get MySQL password
read -s -p "Enter MySQL root password (press Enter if empty): " MYSQL_PASSWORD
echo
echo

if [ -z "$MYSQL_PASSWORD" ]; then
    MYSQL_CMD="mysql -u root"
else
    MYSQL_CMD="mysql -u root -p${MYSQL_PASSWORD}"
fi

# Test connection
if ! $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: MySQL connection failed${NC}"
    exit 1
fi

clear

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     REAL-TIME LOG MONITOR              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo

# Function to display stats
show_stats() {
    echo -e "${BLUE}═══ DATABASE STATISTICS ═══${NC}"
    
    TOTAL=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
    echo -e "${CYAN}Total Records:${NC} $TOTAL"
    
    TODAY=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs WHERE DATE(received_at) = CURDATE();" 2>/dev/null)
    echo -e "${CYAN}Today's Logs:${NC} $TODAY"
    
    HOSTS=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(DISTINCT hostname) FROM remote_logs;" 2>/dev/null)
    echo -e "${CYAN}Unique Hosts:${NC} $HOSTS"
    
    LAST_LOG=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT MAX(received_at) FROM remote_logs;" 2>/dev/null)
    echo -e "${CYAN}Last Log:${NC} $LAST_LOG"
    
    echo
}

# Function to display recent logs
show_recent() {
    echo -e "${BLUE}═══ RECENT LOGS (Last 10) ═══${NC}"
    echo
    
    $MYSQL_CMD -D "${DB_NAME}" -e "
    SELECT 
        id,
        DATE_FORMAT(received_at, '%Y-%m-%d %H:%i:%s') as time,
        hostname,
        facility,
        LEFT(message, 60) as message
    FROM remote_logs 
    ORDER BY id DESC 
    LIMIT 10;
    " 2>/dev/null | tail -n +2 | while IFS=$'\t' read -r id time hostname facility message; do
        echo -e "${YELLOW}ID:${NC} $id ${YELLOW}│${NC} ${CYAN}$time${NC} ${YELLOW}│${NC} ${GREEN}$hostname${NC}"
        echo -e "  ${BLUE}Facility:${NC} $facility"
        echo -e "  ${NC}$message${NC}"
        echo
    done
}

# Function to monitor new logs
monitor_new() {
    echo -e "${BLUE}═══ MONITORING NEW LOGS (Press Ctrl+C to stop) ═══${NC}"
    echo
    
    LAST_ID=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT IFNULL(MAX(id), 0) FROM remote_logs;" 2>/dev/null)
    
    while true; do
        NEW_LOGS=$($MYSQL_CMD -D "${DB_NAME}" -e "
        SELECT 
            id,
            DATE_FORMAT(received_at, '%H:%i:%s') as time,
            hostname,
            facility,
            LEFT(message, 70) as message
        FROM remote_logs 
        WHERE id > $LAST_ID
        ORDER BY id ASC;
        " 2>/dev/null)
        
        if [ -n "$NEW_LOGS" ]; then
            echo "$NEW_LOGS" | tail -n +2 | while IFS=$'\t' read -r id time hostname facility message; do
                echo -e "${GREEN}[NEW]${NC} ${CYAN}$time${NC} ${YELLOW}$hostname${NC} → $message"
                LAST_ID=$id
            done
        fi
        
        sleep 2
    done
}

# Menu
while true; do
    show_stats
    echo -e "${YELLOW}═══ MENU ═══${NC}"
    echo "1. Show recent logs"
    echo "2. Monitor new logs (real-time)"
    echo "3. Search logs by hostname"
    echo "4. Search logs by keyword"
    echo "5. Show logs by date"
    echo "6. Export logs to CSV"
    echo "7. Clear old logs (older than 30 days)"
    echo "8. Refresh stats"
    echo "9. Exit"
    echo
    read -p "Select option [1-9]: " choice
    
    case $choice in
        1)
            clear
            show_recent
            read -p "Press Enter to continue..."
            clear
            ;;
        2)
            clear
            monitor_new
            ;;
        3)
            echo
            read -p "Enter hostname to search: " search_host
            echo
            $MYSQL_CMD -D "${DB_NAME}" -e "
            SELECT 
                id,
                DATE_FORMAT(received_at, '%Y-%m-%d %H:%i:%s') as time,
                facility,
                message
            FROM remote_logs 
            WHERE hostname LIKE '%${search_host}%'
            ORDER BY id DESC 
            LIMIT 20;
            " 2>/dev/null
            read -p "Press Enter to continue..."
            clear
            ;;
        4)
            echo
            read -p "Enter keyword to search: " keyword
            echo
            $MYSQL_CMD -D "${DB_NAME}" -e "
            SELECT 
                id,
                DATE_FORMAT(received_at, '%Y-%m-%d %H:%i:%s') as time,
                hostname,
                facility,
                message
            FROM remote_logs 
            WHERE message LIKE '%${keyword}%'
            ORDER BY id DESC 
            LIMIT 20;
            " 2>/dev/null
            read -p "Press Enter to continue..."
            clear
            ;;
        5)
            echo
            read -p "Enter date (YYYY-MM-DD): " search_date
            echo
            $MYSQL_CMD -D "${DB_NAME}" -e "
            SELECT 
                id,
                DATE_FORMAT(received_at, '%H:%i:%s') as time,
                hostname,
                facility,
                LEFT(message, 60) as message
            FROM remote_logs 
            WHERE DATE(received_at) = '${search_date}'
            ORDER BY id DESC;
            " 2>/dev/null
            read -p "Press Enter to continue..."
            clear
            ;;
        6)
            echo
            EXPORT_FILE="/tmp/logs_export_$(date +%Y%m%d_%H%M%S).csv"
            $MYSQL_CMD -D "${DB_NAME}" -e "
            SELECT 
                id,
                received_at,
                hostname,
                facility,
                message,
                port
            FROM remote_logs 
            ORDER BY id DESC
            INTO OUTFILE '${EXPORT_FILE}'
            FIELDS TERMINATED BY ','
            ENCLOSED BY '\"'
            LINES TERMINATED BY '\n';
            " 2>/dev/null
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Logs exported to: ${EXPORT_FILE}${NC}"
            else
                # Alternative export method
                $MYSQL_CMD -D "${DB_NAME}" -e "
                SELECT 
                    id,
                    received_at,
                    hostname,
                    facility,
                    message,
                    port
                FROM remote_logs 
                ORDER BY id DESC;
                " 2>/dev/null > "${EXPORT_FILE}"
                echo -e "${GREEN}Logs exported to: ${EXPORT_FILE}${NC}"
            fi
            read -p "Press Enter to continue..."
            clear
            ;;
        7)
            echo
            read -p "Are you sure you want to delete logs older than 30 days? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                DELETED=$($MYSQL_CMD -D "${DB_NAME}" -se "
                DELETE FROM remote_logs 
                WHERE received_at < DATE_SUB(NOW(), INTERVAL 30 DAY);
                SELECT ROW_COUNT();
                " 2>/dev/null | tail -1)
                echo -e "${GREEN}Deleted $DELETED old logs${NC}"
            else
                echo "Cancelled"
            fi
            read -p "Press Enter to continue..."
            clear
            ;;
        8)
            clear
            ;;
        9)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            clear
            ;;
    esac
done