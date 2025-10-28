#!/bin/bash

# Remote Logs API - Updated Installer (No Package Installs)
# This script assumes PHP, Apache, and MySQL/MariaDB are already installed.
# It will NOT install or restart these services. Other behavior is kept the same
# as the full installer: DB/table setup, API files deployment, basic tests.

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (same defaults as full installer)
DB_NAME="logger_db"
API_SECRET_KEY="sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"
API_DIR="/var/www/html/api"
MYSQL_ROOT_PASSWORD=""

# Helpers
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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Start
clear
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} Remote Logs API Updated Installer (No-Install) ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo

# Capture MySQL root password (optional)
print_step "MySQL Configuration..."
echo
read -s -p "Enter MySQL root password (press Enter if empty): " MYSQL_ROOT_PASSWORD || true
echo
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    print_warning "Using empty password for MySQL root user"
else
    print_status "MySQL password captured (length: ${#MYSQL_ROOT_PASSWORD})"
fi
echo

# Verify PHP present
print_step "Checking PHP..."
if command_exists php; then
    php -v | head -n1 || true
    print_status "PHP detected"
else
    print_error "PHP not found. Please install PHP before running this script."
    exit 1
fi
echo

# Verify Apache present (do not install or restart)
print_step "Checking Apache..."
if command_exists apache2 || command_exists httpd; then
    if systemctl is-active --quiet apache2 || systemctl is-active --quiet httpd; then
        print_status "Apache service is running"
    else
        print_warning "Apache installed but not running. Start it manually if needed."
    fi
else
    print_warning "Apache not detected. API files will be created, but serving endpoint may fail until Apache is installed and running."
fi
echo

# Prepare MySQL command and verify connectivity (do not install or restart)
print_step "Testing MySQL connectivity..."
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    MYSQL_CMD="mysql -u root"
else
    MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
fi

if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    print_status "MySQL connection test successful"
else
    print_error "MySQL connection test failed. Ensure MySQL/MariaDB is installed and running, then re-run."
    exit 1
fi
echo

## Database creation only (no remote_logs)
print_step "Ensuring database exists..."
DB_EXISTS=$($MYSQL_CMD -e "SHOW DATABASES LIKE '${DB_NAME}';" 2>/dev/null | grep -c "${DB_NAME}" || true)
if [ "$DB_EXISTS" -eq 0 ]; then
    print_status "Creating database '${DB_NAME}'..."
    $MYSQL_CMD << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME}
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;
EOF
    print_status "Database created"
else
    print_warning "Database '${DB_NAME}' already exists"
fi
echo

## Create project tables using existing setup scripts
print_step "Creating project tables (collectors, log_mirror, parsed_logs, devices)..."
if php setup_collector.php; then
    print_status "Collector-related tables ensured."
else
    print_warning "setup_collector.php failed; check PHP errors."
fi

# Optional: setup parsing patterns and field rules if scripts exist
if [ -f "setup_parsing_rules.php" ]; then
    if php setup_parsing_rules.php; then
        print_status "Parsing rules added."
    else
        print_warning "setup_parsing_rules.php failed; continuing."
    fi
fi

if [ -f "setup_field_rules.php" ]; then
    if php setup_field_rules.php; then
        print_status "Field rules added."
    else
        print_warning "setup_field_rules.php failed; continuing."
    fi
fi
echo

API_ENABLE="${API_ENABLE:-0}"
if [ "$API_ENABLE" = "1" ]; then
print_step "Setting up API directory..."
if [ ! -d "$API_DIR" ]; then
    mkdir -p "$API_DIR"
    print_status "API directory created: $API_DIR"
else
    print_warning "API directory already exists: $API_DIR"
fi
echo

print_step "Creating connection.php..."
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
        $dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4";
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
        ];
        $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
        return $pdo;
    } catch (PDOException $e) {
        error_log("Database connection failed: " . $e->getMessage());
        return null;
    }
}

/**
 * Validate API secret key
 */
function validateAPIKey($providedKey) {
    return hash_equals(API_SECRET_KEY, $providedKey);
}
?>
EOF
print_status "connection.php created"
echo

print_step "Creating api.php..."
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
print_status "api.php created"
echo

# Permissions (no service restart)
print_step "Setting file permissions..."
chown -R www-data:www-data "$API_DIR" 2>/dev/null || print_warning "chown failed (insufficient privileges?) — continuing"
chmod 644 "$API_DIR"/*.php 2>/dev/null || true
chmod 755 "$API_DIR" 2>/dev/null || true
print_status "Permissions step completed"
echo

# Test DB connection from PHP
print_step "Testing database connection via PHP..."
DB_TEST=$(php -r "
require_once '$API_DIR/connection.php';
$pdo = getDBConnection();
if ($pdo) {
    $stmt = $pdo->query('SELECT 1 as count');
    $result = $stmt->fetch();
    echo 'SUCCESS:' . $result['count'];
} else {
    echo 'FAILED';
}
" 2>&1 || true)

if [[ "$DB_TEST" == SUCCESS:* ]]; then
    COUNT=${DB_TEST#SUCCESS:}
    print_status "Database connection test passed (${COUNT} records found)"
else
    print_warning "Database connection test returned: $DB_TEST"
fi
echo

# Test API endpoint (best-effort; do not restart Apache)
print_step "Testing API endpoint (if Apache running)..."
API_RESPONSE=$(curl -s -X POST http://localhost/api/api.php \
    -H "Content-Type: application/json" \
    -d "{\"secret_key\": \"${API_SECRET_KEY}\"}" 2>&1 || true)

if echo "$API_RESPONSE" | grep -q '"success": true'; then
    print_status "API endpoint test passed"
else
    print_warning "API test did not pass. Ensure Apache is running and serving $API_DIR."
    echo "$API_RESPONSE"
fi
echo

fi # end API_ENABLE

# Summary (no restarts performed)
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
FINAL_COUNT=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM collectors;" 2>/dev/null || echo 0)

clear
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     UPDATED INSTALLER COMPLETED (NO INSTALLS)      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}═══ API INFORMATION ═══${NC}"
echo "  Server IP:       ${SERVER_IP}"
echo "  Local Endpoint:  http://localhost/api/api.php"
echo "  Remote Endpoint: http://${SERVER_IP}/api/api.php"
echo "  Secret Key:      ${API_SECRET_KEY}"
echo
echo -e "${BLUE}═══ DATABASE INFORMATION ═══${NC}"
echo "  Database Name:   ${DB_NAME}"
echo "  Collectors:      ${FINAL_COUNT}"
echo "  User:            root"
echo
echo -e "${YELLOW}Notes:${NC}"
echo "- This script did NOT install or restart PHP/Apache/MySQL."
echo "- If the API test failed, ensure Apache is running and serving ${API_DIR}."
echo "- If DB steps failed, ensure MySQL/MariaDB is running and credentials are valid."
echo
print_success "Updated installer finished successfully."
echo


