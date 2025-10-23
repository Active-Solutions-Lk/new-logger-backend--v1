#!/bin/bash

# Remote Logs API - Installation Script
# Clean version without interactive prompts

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_NAME="syslog_db"
API_SECRET_KEY="sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"
API_DIR="/var/www/html/api"
MYSQL_ROOT_PASSWORD=""

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if database exists
database_exists() {
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        mysql -u root -e "USE ${DB_NAME};" 2>/dev/null
    else
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${DB_NAME};" 2>/dev/null
    fi
    return $?
}

# Function to check if table exists
table_exists() {
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        mysql -u root -D "${DB_NAME}" -e "DESCRIBE remote_logs;" 2>/dev/null
    else
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -D "${DB_NAME}" -e "DESCRIBE remote_logs;" 2>/dev/null
    fi
    return $?
}

# Start installation
clear
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Remote Logs API Installation   ${NC}"
echo -e "${GREEN}================================${NC}"
echo

print_step "Starting automated installation process..."
echo

# Get MySQL root password
print_step "MySQL Configuration Required..."
echo
read -s -p "Enter MySQL root password (press Enter if empty): " MYSQL_ROOT_PASSWORD
echo
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    print_warning "Using empty password for MySQL root user"
else
    print_status "MySQL password captured (length: ${#MYSQL_ROOT_PASSWORD})"
fi
echo

# Step 1: Update system packages
print_step "Step 1: Updating system packages..."
if apt update >/dev/null 2>&1; then
    print_status "System packages updated successfully"
else
    print_error "Failed to update system packages"
    exit 1
fi
echo

# Step 2: Install Apache2
print_step "Step 2: Installing Apache2 web server..."
if command_exists apache2; then
    print_warning "Apache2 is already installed"
    if systemctl is-active --quiet apache2; then
        print_status "Apache2 service is running"
    else
        systemctl start apache2
        systemctl enable apache2
        print_status "Apache2 service started"
    fi
else
    if apt install -y apache2 >/dev/null 2>&1; then
        systemctl start apache2
        systemctl enable apache2
        print_status "Apache2 installed and started"
    else
        print_error "Failed to install Apache2"
        exit 1
    fi
fi
echo

# Step 3: Install PHP and extensions
print_step "Step 3: Installing PHP and required extensions..."
REQUIRED_PHP_PACKAGES="php libapache2-mod-php php-mysql php-json php-curl"
MISSING_PACKAGES=""

for package in $REQUIRED_PHP_PACKAGES; do
    if ! dpkg -l | grep -q "^ii.*$package "; then
        MISSING_PACKAGES="$MISSING_PACKAGES $package"
    fi
done

if [ -n "$MISSING_PACKAGES" ]; then
    print_status "Installing missing PHP packages:$MISSING_PACKAGES"
    if apt install -y $MISSING_PACKAGES >/dev/null 2>&1; then
        print_status "PHP packages installed successfully"
    else
        print_error "Failed to install PHP packages"
        exit 1
    fi
else
    print_warning "All PHP packages are already installed"
fi

if a2enmod php* >/dev/null 2>&1; then
    print_status "PHP module enabled"
fi
echo

# Step 4: Install MySQL Server
print_step "Step 4: Installing MySQL Server..."
if command_exists mysql; then
    print_warning "MySQL is already installed"
    if systemctl is-active --quiet mysql; then
        print_status "MySQL service is running"
    else
        systemctl start mysql
        systemctl enable mysql
        print_status "MySQL service started"
    fi
else
    if apt install -y mysql-server >/dev/null 2>&1; then
        systemctl start mysql
        systemctl enable mysql
        print_status "MySQL Server installed and started"
    else
        print_error "Failed to install MySQL Server"
        exit 1
    fi
fi
echo

# Step 5: Test MySQL connection
print_step "Step 5: Testing MySQL connection..."
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    MYSQL_CMD="mysql -u root"
else
    MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
fi

if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    print_status "MySQL connection test successful"
else
    print_error "MySQL connection test failed"
    print_error "Please verify your MySQL root password"
    exit 1
fi
echo

# Step 6: Create database and table
print_step "Step 6: Setting up database and table..."
if database_exists; then
    print_warning "Database '${DB_NAME}' already exists"
    if table_exists; then
        print_warning "Table 'remote_logs' already exists"
        RECORD_COUNT=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
        print_status "Current record count: ${RECORD_COUNT}"
    else
        print_status "Creating 'remote_logs' table..."
        $MYSQL_CMD -D "${DB_NAME}" << 'EOF'
CREATE TABLE remote_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    received_at DATETIME NULL,
    hostname VARCHAR(255) NULL,
    facility VARCHAR(50) NULL,
    message TEXT NULL,
    port INT NULL,
    INDEX idx_received_at (received_at),
    INDEX idx_hostname (hostname),
    INDEX idx_facility (facility)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
        print_status "Table 'remote_logs' created successfully"
    fi
else
    print_status "Creating database '${DB_NAME}'..."
    $MYSQL_CMD << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE ${DB_NAME};

CREATE TABLE remote_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    received_at DATETIME NULL,
    hostname VARCHAR(255) NULL,
    facility VARCHAR(50) NULL,
    message TEXT NULL,
    port INT NULL,
    INDEX idx_received_at (received_at),
    INDEX idx_hostname (hostname),
    INDEX idx_facility (facility)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    print_status "Database and table created successfully"
fi

# Insert sample data if table is empty
RECORD_COUNT=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
if [ "$RECORD_COUNT" -eq 0 ]; then
    print_status "Inserting sample data..."
    $MYSQL_CMD -D "${DB_NAME}" << 'EOF'
INSERT INTO remote_logs (received_at, hostname, facility, message, port) VALUES
('2025-09-20 12:24:39', 'DiskStation4', 'user', 'Test message from Synology Syslog Client', 520),
('2025-09-21 07:01:07', 'Active-Com', 'user', 'SYSTEM: System successfully registered', 520),
('2025-09-22 11:04:40', 'Active-Com', 'user', 'User signed in successfully', 520),
('2025-09-22 19:00:01', 'Active-Com', 'user', 'SYSTEM: Shutdown triggered by schedule', 520),
('2025-09-22 19:00:10', 'Active-Com', 'user', 'SYSTEM: USB Copy service stopped', 520),
('2025-09-23 07:02:07', 'Active-Com', 'user', 'SYSTEM: DDNS registration successful', 520);
EOF
    print_status "Sample data inserted (6 records)"
fi
echo

# Step 7: Create API directory
print_step "Step 7: Setting up API directory..."
if [ ! -d "$API_DIR" ]; then
    mkdir -p "$API_DIR"
    print_status "API directory created: $API_DIR"
else
    print_warning "API directory already exists: $API_DIR"
fi
echo

# Step 8: Create connection.php
print_step "Step 8: Creating connection.php..."
cat > "$API_DIR/connection.php" << EOF
<?php
/**
 * Database Connection Configuration
 */

// Database configuration
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '${MYSQL_ROOT_PASSWORD}');
define('DB_NAME', '${DB_NAME}');

// Secret key for API authentication
define('API_SECRET_KEY', '${API_SECRET_KEY}');

/**
 * Get database connection
 */
function getDBConnection() {
    try {
        \$dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4";
        \$options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
        ];
        
        \$pdo = new PDO(\$dsn, DB_USER, DB_PASS, \$options);
        return \$pdo;
    } catch (PDOException \$e) {
        error_log("Database connection failed: " . \$e->getMessage());
        return null;
    }
}

/**
 * Validate API secret key
 */
function validateAPIKey(\$providedKey) {
    return hash_equals(API_SECRET_KEY, \$providedKey);
}
?>
EOF
print_status "connection.php created successfully"
echo

# Step 9: Create api.php
print_step "Step 9: Creating api.php..."
cat > "$API_DIR/api.php" << 'EOFAPI'
<?php
/**
 * Remote Logs API Endpoint
 */

require_once 'connection.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'Method not allowed', 'code' => 'METHOD_NOT_ALLOWED']);
    exit;
}

function sendResponse($success, $data = null, $error = null, $code = null, $httpCode = 200) {
    http_response_code($httpCode);
    $response = ['success' => $success];
    if ($data !== null) $response['data'] = $data;
    if ($error !== null) $response['error'] = $error;
    if ($code !== null) $response['code'] = $code;
    echo json_encode($response, JSON_PRETTY_PRINT);
    exit;
}

try {
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        sendResponse(false, null, 'Invalid JSON format', 'INVALID_JSON', 400);
    }
    
    if (!isset($data['secret_key'])) {
        sendResponse(false, null, 'Secret key is required', 'MISSING_SECRET_KEY', 400);
    }
    
    if (!validateAPIKey($data['secret_key'])) {
        sendResponse(false, null, 'Invalid secret key', 'INVALID_SECRET_KEY', 401);
    }
    
    $pdo = getDBConnection();
    if (!$pdo) {
        sendResponse(false, null, 'Database connection failed', 'DB_CONNECTION_ERROR', 500);
    }
    
    $lastId = isset($data['last_id']) ? (int)$data['last_id'] : 0;
    $limit = isset($data['limit']) ? min((int)$data['limit'], 1000) : 100;
    
    if ($lastId > 0) {
        $stmt = $pdo->prepare("SELECT id, received_at, hostname, facility, message, port FROM remote_logs WHERE id > ? ORDER BY id ASC LIMIT ?");
        $stmt->execute([$lastId, $limit]);
    } else {
        $stmt = $pdo->prepare("SELECT id, received_at, hostname, facility, message, port FROM remote_logs ORDER BY id ASC LIMIT ?");
        $stmt->execute([$limit]);
    }
    
    $records = $stmt->fetchAll();
    
    if ($lastId > 0) {
        $countStmt = $pdo->prepare("SELECT COUNT(*) as total FROM remote_logs WHERE id > ?");
        $countStmt->execute([$lastId]);
    } else {
        $countStmt = $pdo->query("SELECT COUNT(*) as total FROM remote_logs");
    }
    $totalCount = $countStmt->fetch()['total'];
    
    $responseData = [
        'records' => $records,
        'count' => count($records),
        'total_available' => (int)$totalCount,
        'last_id_requested' => $lastId,
        'limit' => $limit
    ];
    
    if (!empty($records)) {
        $responseData['next_last_id'] = end($records)['id'];
    }
    
    sendResponse(true, $responseData);
    
} catch (PDOException $e) {
    error_log("Database error: " . $e->getMessage());
    sendResponse(false, null, 'Database query failed', 'DB_QUERY_ERROR', 500);
} catch (Exception $e) {
    error_log("General error: " . $e->getMessage());
    sendResponse(false, null, 'Internal server error', 'INTERNAL_ERROR', 500);
}
?>
EOFAPI
print_status "api.php created successfully"
echo

# Step 10: Set file permissions
print_step "Step 10: Setting file permissions..."
chown -R www-data:www-data "$API_DIR"
chmod 644 "$API_DIR"/*.php
chmod 755 "$API_DIR"
print_status "File permissions set successfully"
echo

# Step 11: Restart Apache
print_step "Step 11: Restarting Apache..."
if a2enmod rewrite >/dev/null 2>&1; then
    print_status "Apache rewrite module enabled"
fi
systemctl restart apache2
print_status "Apache2 restarted successfully"
echo

# Step 12: Test database connection from PHP
print_step "Step 12: Testing database connection from API..."
DB_TEST=$(php -r "
require_once '$API_DIR/connection.php';
\$pdo = getDBConnection();
if (\$pdo) {
    \$stmt = \$pdo->query('SELECT COUNT(*) as count FROM remote_logs');
    \$result = \$stmt->fetch();
    echo 'SUCCESS:' . \$result['count'];
} else {
    echo 'FAILED';
}
" 2>&1)

if [[ "$DB_TEST" == SUCCESS:* ]]; then
    COUNT=${DB_TEST#SUCCESS:}
    print_status "Database connection test passed (${COUNT} records found)"
else
    print_error "Database connection test failed: $DB_TEST"
    exit 1
fi
echo

# Step 13: Test API endpoint
print_step "Step 13: Testing API endpoint..."
sleep 1

API_RESPONSE=$(curl -s -X POST http://localhost/api/api.php \
    -H "Content-Type: application/json" \
    -d "{\"secret_key\": \"${API_SECRET_KEY}\"}" 2>&1)

if echo "$API_RESPONSE" | grep -q '"success": true'; then
    print_status "API endpoint test passed"
    RECORD_COUNT=$(echo "$API_RESPONSE" | grep -o '"count": [0-9]*' | cut -d: -f2 | tr -d ' ')
    print_status "API returned ${RECORD_COUNT} records"
else
    print_warning "API test returned unexpected response"
    echo "$API_RESPONSE"
fi
echo

# Step 14: Create test scripts
print_step "Step 14: Creating test and utility scripts..."

# Create API test script
cat > "$API_DIR/test_api.sh" << 'EOFTEST'
#!/bin/bash

echo "=============================="
echo "  Remote Logs API Test Suite"
echo "=============================="
echo

SECRET_KEY="sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"

echo "Test 1: Get all records"
echo "========================"
curl -s -X POST http://localhost/api/api.php \
  -H "Content-Type: application/json" \
  -d "{\"secret_key\": \"$SECRET_KEY\"}" | python3 -m json.tool
echo
echo

echo "Test 2: Get records with last_id=2"
echo "==================================="
curl -s -X POST http://localhost/api/api.php \
  -H "Content-Type: application/json" \
  -d "{\"secret_key\": \"$SECRET_KEY\", \"last_id\": 2}" | python3 -m json.tool
echo
echo

echo "Test 3: Get limited records (limit=3)"
echo "====================================="
curl -s -X POST http://localhost/api/api.php \
  -H "Content-Type: application/json" \
  -d "{\"secret_key\": \"$SECRET_KEY\", \"limit\": 3}" | python3 -m json.tool
echo
echo

echo "Test 4: Invalid secret key (should fail)"
echo "========================================"
curl -s -X POST http://localhost/api/api.php \
  -H "Content-Type: application/json" \
  -d '{"secret_key": "wrong_key"}' | python3 -m json.tool
echo

echo "=============================="
echo "  Test Suite Completed"
echo "=============================="
EOFTEST

chmod +x "$API_DIR/test_api.sh"
print_status "Test script created: $API_DIR/test_api.sh"

# Create cron job setup script
cat > "$API_DIR/setup_cron.sh" << 'EOFCRON'
#!/bin/bash

# Cron Job Setup Script for Log Collection
# This script sets up automated log collection

echo "Setting up cron job for log collection..."

# Define the cron job
CRON_JOB="*/5 * * * * /usr/bin/php /var/www/html/api/log_fetcher.php >> /var/log/log_fetcher.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "log_fetcher.php"; then
    echo "Cron job already exists"
else
    # Add the cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job added successfully"
    echo "Schedule: Every 5 minutes"
fi

# Display current crontab
echo
echo "Current crontab:"
crontab -l

echo
echo "Cron job setup complete!"
echo "Logs will be collected every 5 minutes"
echo "Check logs at: /var/log/log_fetcher.log"
EOFCRON

chmod +x "$API_DIR/setup_cron.sh"
print_status "Cron setup script created: $API_DIR/setup_cron.sh"

# Create log fetcher script
cat > "$API_DIR/log_fetcher.php" << 'EOFFETCHER'
<?php
/**
 * Log Fetcher - Automated Log Collection Script
 * Runs via cron job to fetch logs from remote API
 */

require_once 'connection.php';

// Configuration
$REMOTE_API_URL = "http://YOUR_REMOTE_SERVER/api/api.php";
$API_SECRET_KEY = "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d";
$LAST_ID_FILE = "/tmp/last_log_id.txt";

// Function to log messages
function logMessage($message) {
    $timestamp = date('Y-m-d H:i:s');
    echo "[{$timestamp}] {$message}\n";
}

// Get last processed ID
$lastId = 0;
if (file_exists($LAST_ID_FILE)) {
    $lastId = (int)file_get_contents($LAST_ID_FILE);
}

logMessage("Starting log fetch from ID: {$lastId}");

// Prepare API request
$requestData = [
    'secret_key' => $API_SECRET_KEY,
    'last_id' => $lastId,
    'limit' => 100
];

// Make API request
$ch = curl_init($REMOTE_API_URL);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($requestData));
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($httpCode !== 200) {
    logMessage("ERROR: API returned HTTP {$httpCode}");
    exit(1);
}

$data = json_decode($response, true);

if (!$data || !isset($data['success']) || !$data['success']) {
    logMessage("ERROR: API request failed");
    exit(1);
}

$records = $data['data']['records'] ?? [];
$count = count($records);

logMessage("Fetched {$count} new records");

if ($count > 0) {
    // Insert records into local database
    $pdo = getDBConnection();
    if (!$pdo) {
        logMessage("ERROR: Database connection failed");
        exit(1);
    }
    
    $stmt = $pdo->prepare("
        INSERT INTO remote_logs (id, received_at, hostname, facility, message, port)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        received_at = VALUES(received_at),
        hostname = VALUES(hostname),
        facility = VALUES(facility),
        message = VALUES(message),
        port = VALUES(port)
    ");
    
    $inserted = 0;
    foreach ($records as $record) {
        try {
            $stmt->execute([
                $record['id'],
                $record['received_at'],
                $record['hostname'],
                $record['facility'],
                $record['message'],
                $record['port']
            ]);
            $inserted++;
        } catch (PDOException $e) {
            logMessage("ERROR inserting record ID {$record['id']}: " . $e->getMessage());
        }
    }
    
    logMessage("Inserted/Updated {$inserted} records");
    
    // Update last processed ID
    $newLastId = $data['data']['next_last_id'] ?? $lastId;
    file_put_contents($LAST_ID_FILE, $newLastId);
    logMessage("Updated last_id to: {$newLastId}");
}

logMessage("Log fetch completed successfully");
?>
EOFFETCHER

chmod +x "$API_DIR/log_fetcher.php"
print_status "Log fetcher script created: $API_DIR/log_fetcher.php"
echo

# Final summary
SERVER_IP=$(hostname -I | awk '{print $1}')
FINAL_COUNT=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)

clear
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   INSTALLATION COMPLETED SUCCESSFULLY  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}═══ API INFORMATION ═══${NC}"
echo "  Server IP:       ${SERVER_IP}"
echo "  Local Endpoint:  http://localhost/api/api.php"
echo "  Remote Endpoint: http://${SERVER_IP}/api/api.php"
echo "  Secret Key:      ${API_SECRET_KEY}"
echo
echo -e "${BLUE}═══ DATABASE INFORMATION ═══${NC}"
echo "  Database Name:   ${DB_NAME}"
echo "  Current Records: ${FINAL_COUNT}"
echo "  User:            root"
echo
echo -e "${BLUE}═══ AVAILABLE SCRIPTS ═══${NC}"
echo "  Test API:        bash ${API_DIR}/test_api.sh"
echo "  Setup Cron:      bash ${API_DIR}/setup_cron.sh"
echo "  Log Fetcher:     php ${API_DIR}/log_fetcher.php"
echo
echo -e "${YELLOW}═══ QUICK TESTS ═══${NC}"
echo
echo "1. Test API locally:"
echo "   curl -X POST http://localhost/api/api.php \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"secret_key\": \"${API_SECRET_KEY}\"}'"
echo
echo "2. Test API remotely:"
echo "   curl -X POST http://${SERVER_IP}/api/api.php \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"secret_key\": \"${API_SECRET_KEY}\"}'"
echo
echo "3. Run full test suite:"
echo "   bash ${API_DIR}/test_api.sh"
echo
echo -e "${YELLOW}═══ FIREWALL CONFIGURATION ═══${NC}"
echo "To allow remote access, run these commands:"
echo "  sudo ufw allow 22/tcp   # SSH (Important!)"
echo "  sudo ufw allow 80/tcp   # HTTP"
echo "  sudo ufw allow 443/tcp  # HTTPS"
echo "  sudo ufw enable"
echo "  sudo ufw reload"
echo
echo -e "${YELLOW}═══ SETUP AUTOMATED LOG COLLECTION ═══${NC}"
echo "1. Edit ${API_DIR}/log_fetcher.php"
echo "2. Update \$REMOTE_API_URL with your remote server"
echo "3. Run: bash ${API_DIR}/setup_cron.sh"
echo
print_success "Installation completed! Your API is ready to use."
echo