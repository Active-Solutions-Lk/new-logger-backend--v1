#!/bin/bash

# Remote Logs API - Simple Installation Script
# This script uses the MySQL root password provided by the user
# NO authentication changes, NO dropping users, NO socket modifications

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Start installation
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Remote Logs API Installation   ${NC}"
echo -e "${GREEN}================================${NC}"
echo

# Get MySQL root password
print_step "MySQL Configuration"
echo
# Add timeout to prevent hanging
read -s -p "Enter MySQL root password (press Enter if empty): " -t 30 MYSQL_ROOT_PASSWORD
# If timeout occurs, set empty password
if [[ $? -gt 128 ]]; then
    echo -e "\n${YELLOW}[INFO]${NC} No input received, using empty password"
    MYSQL_ROOT_PASSWORD=""
fi
echo
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    print_warning "Using empty password for MySQL root user"
    MYSQL_CMD="mysql -u root"
else
    print_status "MySQL password captured (length: ${#MYSQL_ROOT_PASSWORD})"
    MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
fi
echo

# Step 1: Test MySQL connection
print_step "Step 1: Testing MySQL connection..."
if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    print_status "MySQL connection successful"
else
    print_error "MySQL connection failed"
    print_error "Please verify your MySQL root password"
    exit 1
fi
echo

# Step 2: Update system packages
print_step "Step 2: Updating system packages..."
if apt update >/dev/null 2>&1; then
    print_status "System packages updated"
else
    print_warning "Failed to update packages (continuing anyway)"
fi
echo

# Step 3: Install required packages
print_step "Step 3: Installing required packages..."
REQUIRED_PACKAGES="apache2 php libapache2-mod-php php-mysql php-json php-curl"
MISSING_PACKAGES=""

for package in $REQUIRED_PACKAGES; do
    if ! dpkg -l | grep -q "^ii.*$package "; then
        MISSING_PACKAGES="$MISSING_PACKAGES $package"
    fi
done

if [ -n "$MISSING_PACKAGES" ]; then
    print_status "Installing:$MISSING_PACKAGES"
    if apt install -y $MISSING_PACKAGES >/dev/null 2>&1; then
        print_status "Packages installed successfully"
    else
        print_error "Failed to install some packages"
        exit 1
    fi
else
    print_status "All required packages already installed"
fi
echo

# Step 4: Ensure services are running
print_step "Step 4: Starting services..."

if systemctl is-active --quiet apache2; then
    print_status "Apache2 is running"
else
    systemctl start apache2
    systemctl enable apache2
    print_status "Apache2 started"
fi

if systemctl is-active --quiet mysql; then
    print_status "MySQL is running"
else
    systemctl start mysql
    systemctl enable mysql
    print_status "MySQL started"
fi
echo

# Step 5: Create database and table
print_step "Step 5: Setting up database..."

# Check if database exists
DB_EXISTS=$($MYSQL_CMD -e "SHOW DATABASES LIKE '${DB_NAME}';" 2>/dev/null | grep -c "${DB_NAME}")

if [ "$DB_EXISTS" -eq 0 ]; then
    print_status "Creating database '${DB_NAME}'..."
    $MYSQL_CMD << EOF
CREATE DATABASE ${DB_NAME} 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;
EOF
    print_status "Database created"
else
    print_warning "Database '${DB_NAME}' already exists"
fi

# Check if table exists
TABLE_EXISTS=$($MYSQL_CMD -D "${DB_NAME}" -e "SHOW TABLES LIKE 'remote_logs';" 2>/dev/null | grep -c "remote_logs")

if [ "$TABLE_EXISTS" -eq 0 ]; then
    print_status "Creating table 'remote_logs'..."
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
    print_status "Table created"
else
    print_warning "Table 'remote_logs' already exists"
fi

# Count records
RECORD_COUNT=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
print_status "Current records: ${RECORD_COUNT}"

# Insert sample data if empty
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

# Step 6: Create API directory
print_step "Step 6: Creating API directory..."
if [ ! -d "$API_DIR" ]; then
    mkdir -p "$API_DIR"
    print_status "API directory created: $API_DIR"
else
    print_warning "API directory already exists"
fi
echo

# Step 7: Create connection.php
print_step "Step 7: Creating connection.php..."
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
print_status "connection.php created"
echo

# Step 8: Create api.php
print_step "Step 8: Creating api.php..."
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

# Step 9: Set permissions
print_step "Step 9: Setting file permissions..."
chown -R www-data:www-data "$API_DIR"
chmod 644 "$API_DIR"/*.php
chmod 755 "$API_DIR"
print_status "Permissions set"
echo

# Step 10: Restart Apache
print_step "Step 10: Restarting Apache..."
systemctl restart apache2
print_status "Apache restarted"
echo

# Step 11: Configure firewall
print_step "Step 11: Configuring firewall..."
if command_exists ufw; then
    if sudo ufw status | grep -q "Status: active"; then
        print_status "Configuring firewall rules..."
        sudo ufw allow 80/tcp >/dev/null 2>&1 && print_status "Allowed HTTP (port 80)"
        sudo ufw allow 443/tcp >/dev/null 2>&1 && print_status "Allowed HTTPS (port 443)"
        sudo ufw reload >/dev/null 2>&1
    else
        print_warning "UFW is not active. To enable: sudo ufw enable"
    fi
else
    print_warning "UFW not installed. Install with: sudo apt install ufw"
fi
echo

# Step 12: Test the API
print_step "Step 12: Testing API..."
sleep 2

TEST_RESPONSE=$(curl -s -X POST http://localhost/api/api.php \
    -H "Content-Type: application/json" \
    -d "{\"secret_key\": \"${API_SECRET_KEY}\"}")

if echo "$TEST_RESPONSE" | grep -q '"success": true'; then
    print_status "API test PASSED"
else
    print_warning "API test returned unexpected response"
    echo "Response: $TEST_RESPONSE"
fi
echo

# Final summary
SERVER_IP=$(hostname -I | awk '{print $1}')
FINAL_COUNT=$($MYSQL_CMD -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE!       ${NC}"
echo -e "${GREEN}================================${NC}"
echo
echo -e "${BLUE}API Details:${NC}"
echo "  Local:  http://localhost/api/api.php"
echo "  Remote: http://${SERVER_IP}/api/api.php"
echo "  Secret: ${API_SECRET_KEY}"
echo
echo -e "${BLUE}Database:${NC}"
echo "  Name: ${DB_NAME}"
echo "  Records: ${FINAL_COUNT}"
echo "  User: root"
echo
echo -e "${YELLOW}Test Command:${NC}"
echo "curl -X POST http://localhost/api/api.php \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"secret_key\": \"${API_SECRET_KEY}\"}'"
echo