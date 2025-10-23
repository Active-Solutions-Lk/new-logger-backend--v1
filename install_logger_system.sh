#!/bin/bash

# Remote Logs API - Automated Installation Script
# This script installs and configures all required components
# Author: Auto-generated for Remote Logs API
# Date: $(date)

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
MYSQL_ROOT_PASSWORD=""  # Will be requested from user

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

# Function to check if MySQL service is running
check_mysql_service() {
    if systemctl is-active --quiet mysql; then
        return 0
    else
        return 1
    fi
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

# Function to test API endpoint
test_api() {
    local response=$(curl -s -X POST http://localhost/api/api.php \
        -H "Content-Type: application/json" \
        -d "{\"secret_key\": \"${API_SECRET_KEY}\"}" 2>/dev/null)
    
    if echo "$response" | grep -q '"success": true'; then
        return 0
    else
        return 1
    fi
}

# Start installation
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Remote Logs API Installation   ${NC}"
echo -e "${GREEN}================================${NC}"
echo

# Get MySQL root password
print_step "MySQL Configuration"
echo
read -s -p "Enter MySQL root password (press Enter if empty): " MYSQL_ROOT_PASSWORD
echo
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    print_warning "Using empty password for MySQL root user"
    MYSQL_CMD="mysql -u root"
else
    print_status "MySQL password captured (length: ${#MYSQL_ROOT_PASSWORD})"
    MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
fi
echo

print_step "Starting automated installation process..."
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
        print_status "Starting Apache2 service..."
        systemctl start apache2
        systemctl enable apache2
    fi
else
    if apt install -y apache2 >/dev/null 2>&1; then
        print_status "Apache2 installed successfully"
        systemctl start apache2
        systemctl enable apache2
        print_status "Apache2 service started and enabled"
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

# Enable PHP module
if a2enmod php* >/dev/null 2>&1; then
    print_status "PHP module enabled"
fi
echo

# Step 4: Install MySQL Server
print_step "Step 4: Installing MySQL Server..."
if command_exists mysql; then
    print_warning "MySQL is already installed"
    if check_mysql_service; then
        print_status "MySQL service is running"
    else
        print_status "Starting MySQL service..."
        systemctl start mysql
        systemctl enable mysql
    fi
else
    print_status "Installing MySQL Server..."
    # Set debconf for automated installation
    echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    
    if apt install -y mysql-server >/dev/null 2>&1; then
        print_status "MySQL Server installed successfully"
        systemctl start mysql
        systemctl enable mysql
        print_status "MySQL service started and enabled"
        
        # Secure installation (basic)
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        print_status "MySQL basic security applied"
    else
        print_error "Failed to install MySQL Server"
        exit 1
    fi
fi
echo

# Step 5: Test MySQL connection
print_step "Step 5: Testing MySQL connection..."
if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    print_status "MySQL connection test successful"
else
    print_error "MySQL connection test failed"
    print_error "Please check MySQL installation and root password"
    exit 1
fi
echo

# Step 5.1: Fix MySQL root authentication for PHP
print_step "Step 5.1: Configuring MySQL authentication for PHP..."
CURRENT_PLUGIN=$(sudo mysql -u root -se "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" 2>/dev/null)

if [ "$CURRENT_PLUGIN" = "auth_socket" ] || [ "$CURRENT_PLUGIN" = "unix_socket" ]; then
    print_warning "MySQL root user is using socket authentication"
    print_status "Changing to mysql_native_password for PHP compatibility..."
    
    sudo mysql -u root << 'EOSQL'
-- Change root authentication method
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';

-- Flush privileges
FLUSH PRIVILEGES;
EOSQL
    
    if [ $? -eq 0 ]; then
        print_status "MySQL authentication method updated successfully"
        
        # Verify the change
        if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
            print_status "Verified: MySQL root can now connect with empty password"
        else
            print_error "Failed to verify MySQL connection"
            exit 1
        fi
    else
        print_error "Failed to update MySQL authentication method"
        exit 1
    fi
else
    print_status "MySQL root authentication is already configured correctly"
fi
echo

# Step 6: Create database and table
print_step "Step 6: Setting up database and table..."
if database_exists; then
    print_warning "Database '${DB_NAME}' already exists"
    if table_exists; then
        print_warning "Table 'remote_logs' already exists"
        # Count existing records
        if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
            RECORD_COUNT=$(mysql -u root -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
        else
            RECORD_COUNT=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
        fi
        print_status "Current record count: ${RECORD_COUNT}"
    else
        print_status "Creating 'remote_logs' table..."
        if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
            mysql -u root -D "${DB_NAME}" << 'EOF'
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
        else
            mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -D "${DB_NAME}" << 'EOF'
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
        fi
        print_status "Table 'remote_logs' created successfully"
    fi
else
    print_status "Creating database '${DB_NAME}'..."
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        mysql -u root << EOF
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
    else
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << EOF
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
    fi
    print_status "Database and table created successfully"
fi

# Insert sample data if table is empty
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    RECORD_COUNT=$(mysql -u root -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
else
    RECORD_COUNT=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
fi

if [ "$RECORD_COUNT" -eq 0 ]; then
    print_status "Inserting sample data..."
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        mysql -u root -D "${DB_NAME}" << 'EOF'
INSERT INTO remote_logs (received_at, hostname, facility, message, port) VALUES
('2025-09-20 12:24:39', 'DiskStation4', 'user', 'Test message from Synology Syslog Client from (112.134.220.176)', 520),
('2025-09-21 07:01:07', 'Active-Com', 'user', 'SYSTEM: System successfully registered [112.134.220.176] to [cont.synology.me] in DDNS server [Synology].', 520),
('2025-09-22 11:04:40', 'Active-Com', 'user', 'User [Active] from [192.168.0.47] signed in to [DSM] successfully via [password].', 520),
('2025-09-22 19:00:01', 'Active-Com', 'user', 'SYSTEM: System start counting down to shutdown. This is triggered by Power Schedule.', 520),
('2025-09-22 19:00:10', 'Active-Com', 'user', 'SYSTEM: [USB Copy] service was stopped.', 520),
('2025-09-23 07:02:07', 'Active-Com', 'user', 'SYSTEM: System successfully registered [112.134.220.176] to [cont.synology.me] in DDNS server [Synology].', 520);
EOF
    else
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -D "${DB_NAME}" << 'EOF'
INSERT INTO remote_logs (received_at, hostname, facility, message, port) VALUES
('2025-09-20 12:24:39', 'DiskStation4', 'user', 'Test message from Synology Syslog Client from (112.134.220.176)', 520),
('2025-09-21 07:01:07', 'Active-Com', 'user', 'SYSTEM: System successfully registered [112.134.220.176] to [cont.synology.me] in DDNS server [Synology].', 520),
('2025-09-22 11:04:40', 'Active-Com', 'user', 'User [Active] from [192.168.0.47] signed in to [DSM] successfully via [password].', 520),
('2025-09-22 19:00:01', 'Active-Com', 'user', 'SYSTEM: System start counting down to shutdown. This is triggered by Power Schedule.', 520),
('2025-09-22 19:00:10', 'Active-Com', 'user', 'SYSTEM: [USB Copy] service was stopped.', 520),
('2025-09-23 07:02:07', 'Active-Com', 'user', 'SYSTEM: System successfully registered [112.134.220.176] to [cont.synology.me] in DDNS server [Synology].', 520);
EOF
    fi
    print_status "Sample data inserted successfully"
else
    print_status "Database already contains ${RECORD_COUNT} records, skipping sample data insertion"
fi
echo

# Step 7: Create API directory
print_step "Step 7: Setting up API directory..."
if [ -d "$API_DIR" ]; then
    print_warning "API directory already exists: $API_DIR"
else
    if mkdir -p "$API_DIR"; then
        print_status "API directory created: $API_DIR"
    else
        print_error "Failed to create API directory"
        exit 1
    fi
fi
echo

# Step 8: Create connection.php
print_step "Step 8: Creating connection.php..."
cat > "$API_DIR/connection.php" << EOF
<?php
/**
 * Database Connection Configuration
 * Separate connection file for security and modularity
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
 * @return PDO|null
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
 * @param string \$providedKey
 * @return bool
 */
function validateAPIKey(\$providedKey) {
    return hash_equals(API_SECRET_KEY, \$providedKey);
}
?>
EOF

if [ -f "$API_DIR/connection.php" ]; then
    print_status "connection.php created successfully"
else
    print_error "Failed to create connection.php"
    exit 1
fi
echo

# Step 9: Create api.php
print_step "Step 9: Creating api.php..."
cat > "$API_DIR/api.php" << 'EOF'
<?php
/**
 * Remote Logs API Endpoint
 * Accepts POST requests with secret key authentication
 * Returns log records after specified LAST_ID
 */

// Include database connection
require_once 'connection.php';

// Set proper headers for API response
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'error' => 'Method not allowed. Only POST requests are accepted.',
        'code' => 'METHOD_NOT_ALLOWED'
    ]);
    exit;
}

// Function to send JSON response
function sendResponse($success, $data = null, $error = null, $code = null, $httpCode = 200) {
    http_response_code($httpCode);
    $response = ['success' => $success];
    
    if ($data !== null) {
        $response['data'] = $data;
    }
    
    if ($error !== null) {
        $response['error'] = $error;
    }
    
    if ($code !== null) {
        $response['code'] = $code;
    }
    
    echo json_encode($response, JSON_PRETTY_PRINT);
    exit;
}

try {
    // Get POST data
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    // Check if JSON is valid
    if (json_last_error() !== JSON_ERROR_NONE) {
        sendResponse(false, null, 'Invalid JSON format', 'INVALID_JSON', 400);
    }
    
    // Validate required fields
    if (!isset($data['secret_key'])) {
        sendResponse(false, null, 'Secret key is required', 'MISSING_SECRET_KEY', 400);
    }
    
    // Validate secret key
    if (!validateAPIKey($data['secret_key'])) {
        sendResponse(false, null, 'Invalid secret key', 'INVALID_SECRET_KEY', 401);
    }
    
    // Get database connection
    $pdo = getDBConnection();
    if (!$pdo) {
        sendResponse(false, null, 'Database connection failed', 'DB_CONNECTION_ERROR', 500);
    }
    
    // Check if LAST_ID is provided
    $lastId = isset($data['last_id']) ? (int)$data['last_id'] : 0;
    
    // Set default limit to prevent overwhelming responses
    $limit = isset($data['limit']) ? min((int)$data['limit'], 1000) : 100;
    
    // Prepare SQL query (using ? placeholders to avoid binding issues with LIMIT)
    if ($lastId > 0) {
        $sql = "SELECT id, received_at, hostname, facility, message, port 
                FROM remote_logs 
                WHERE id > ? 
                ORDER BY id ASC 
                LIMIT ?";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$lastId, $limit]);
    } else {
        $sql = "SELECT id, received_at, hostname, facility, message, port 
                FROM remote_logs 
                ORDER BY id ASC 
                LIMIT ?";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$limit]);
    }
    
    $records = $stmt->fetchAll();
    
    // Get total count for information
    if ($lastId > 0) {
        $countStmt = $pdo->prepare("SELECT COUNT(*) as total FROM remote_logs WHERE id > ?");
        $countStmt->execute([$lastId]);
    } else {
        $countStmt = $pdo->query("SELECT COUNT(*) as total FROM remote_logs");
    }
    $totalCount = $countStmt->fetch()['total'];
    
    // Prepare response data
    $responseData = [
        'records' => $records,
        'count' => count($records),
        'total_available' => (int)$totalCount,
        'last_id_requested' => $lastId,
        'limit' => $limit
    ];
    
    // Add next_last_id if there are records
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
EOF

if [ -f "$API_DIR/api.php" ]; then
    print_status "api.php created successfully"
else
    print_error "Failed to create api.php"
    exit 1
fi
echo

# Step 10: Set proper permissions
print_step "Step 10: Setting file permissions..."
if chown -R www-data:www-data "$API_DIR" && chmod -R 644 "$API_DIR"/*.php && chmod 755 "$API_DIR"; then
    print_status "File permissions set successfully"
else
    print_warning "Failed to set some permissions, but continuing..."
fi
echo

# Step 11: Enable Apache modules and restart
print_step "Step 11: Configuring Apache..."
if a2enmod rewrite >/dev/null 2>&1; then
    print_status "Apache rewrite module enabled"
fi

if systemctl restart apache2; then
    print_status "Apache2 restarted successfully"
else
    print_error "Failed to restart Apache2"
    exit 1
fi
echo

# Step 11.1: Configure Firewall for remote access
print_step "Step 11.1: Configuring firewall for remote API access..."

# Check if UFW is installed
if command_exists ufw; then
    print_status "UFW firewall detected"
    
    # Check if UFW is active
    UFW_STATUS=$(sudo ufw status | grep -c "Status: active")
    
    if [ "$UFW_STATUS" -eq 0 ]; then
        print_warning "UFW is installed but not active"
        read -p "Do you want to enable UFW firewall? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Enable UFW
            print_status "Enabling UFW firewall..."
            
            # Allow SSH first to prevent lockout
            sudo ufw allow 22/tcp >/dev/null 2>&1
            print_status "Allowed SSH (port 22)"
            
            # Enable UFW
            sudo ufw --force enable >/dev/null 2>&1
            print_status "UFW firewall enabled"
        else
            print_warning "UFW not enabled - skipping firewall configuration"
        fi
    fi
    
    # Configure firewall rules if UFW is active
    if sudo ufw status | grep -q "Status: active"; then
        print_status "Configuring firewall rules..."
        
        # Allow HTTP (port 80)
        if sudo ufw allow 80/tcp >/dev/null 2>&1; then
            print_status "Allowed HTTP (port 80) for API access"
        fi
        
        # Allow HTTPS (port 443)
        if sudo ufw allow 443/tcp >/dev/null 2>&1; then
            print_status "Allowed HTTPS (port 443) for secure API access"
        fi
        
        # Reload firewall
        sudo ufw reload >/dev/null 2>&1
        print_status "Firewall rules reloaded"
        
        # Show firewall status
        echo
        print_status "Current firewall rules:"
        sudo ufw status numbered | grep -E "(80|443|22)" || true
    fi
else
    print_warning "UFW firewall not installed"
    print_warning "To install UFW: sudo apt install ufw"
    print_warning "Remote API access may be blocked by firewall"
fi
echo

# Step 12: Test database connection from API
print_step "Step 12: Testing database connection from API..."
DB_TEST_RESULT=$(php -r "
require_once '$API_DIR/connection.php';
\$pdo = getDBConnection();
if (\$pdo) {
    \$stmt = \$pdo->query('SELECT COUNT(*) as count FROM remote_logs');
    \$result = \$stmt->fetch();
    echo 'SUCCESS:' . \$result['count'];
} else {
    echo 'FAILED';
}
" 2>/dev/null)

if [[ "$DB_TEST_RESULT" == SUCCESS:* ]]; then
    RECORD_COUNT=${DB_TEST_RESULT#SUCCESS:}
    print_status "Database connection test passed (${RECORD_COUNT} records found)"
else
    print_error "Database connection test failed"
    exit 1
fi
echo

# Step 13: Test API endpoint
print_step "Step 13: Testing API endpoint..."
sleep 2  # Give Apache a moment to fully restart

if test_api; then
    print_status "API endpoint test passed"
else
    print_warning "API endpoint test failed, checking manually..."
    
    # Manual test with more details
    MANUAL_TEST=$(curl -s -w "\n%{http_code}" -X POST http://localhost/api/api.php \
        -H "Content-Type: application/json" \
        -d "{\"secret_key\": \"${API_SECRET_KEY}\"}" 2>/dev/null)
    
    HTTP_CODE=$(echo "$MANUAL_TEST" | tail -n1)
    RESPONSE_BODY=$(echo "$MANUAL_TEST" | head -n -1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$RESPONSE_BODY" | grep -q '"success": true'; then
            print_status "API endpoint test passed on retry"
        else
            print_error "API returned success=false: $RESPONSE_BODY"
            exit 1
        fi
    else
        print_error "API returned HTTP $HTTP_CODE: $RESPONSE_BODY"
        exit 1
    fi
fi
echo

# Step 14: Create test script
print_step "Step 14: Creating test script..."
cat > "$API_DIR/test_api.sh" << EOF
#!/bin/bash

echo "Testing Remote Logs API..."
echo "=========================="
echo

# Test 1: Get all records
echo "Test 1: Getting all records"
curl -X POST http://localhost/api/api.php \\
  -H "Content-Type: application/json" \\
  -d '{
    "secret_key": "${API_SECRET_KEY}"
  }' | jq '.'
echo
echo

# Test 2: Get records after ID 42
echo "Test 2: Getting records after ID 42"
curl -X POST http://localhost/api/api.php \\
  -H "Content-Type: application/json" \\
  -d '{
    "secret_key": "${API_SECRET_KEY}",
    "last_id": 42
  }' | jq '.'
echo
echo

# Test 3: Get limited records
echo "Test 3: Getting limited records (limit: 2)"
curl -X POST http://localhost/api/api.php \\
  -H "Content-Type: application/json" \\
  -d '{
    "secret_key": "${API_SECRET_KEY}",
    "limit": 2
  }' | jq '.'
echo
echo

# Test 4: Test with wrong secret key (should fail)
echo "Test 4: Testing with wrong secret key (should fail)"
curl -X POST http://localhost/api/api.php \\
  -H "Content-Type: application/json" \\
  -d '{
    "secret_key": "wrong_key"
  }' | jq '.'
echo

echo "API testing completed!"
EOF

chmod +x "$API_DIR/test_api.sh"
print_status "Test script created: $API_DIR/test_api.sh"
echo

# Step 15: Final verification
print_step "Step 15: Final system verification..."

# Check all services
SERVICES_OK=true

if ! systemctl is-active --quiet apache2; then
    print_error "Apache2 service is not running"
    SERVICES_OK=false
else
    print_status "Apache2 service: Running"
fi

if ! systemctl is-active --quiet mysql; then
    print_error "MySQL service is not running"
    SERVICES_OK=false
else
    print_status "MySQL service: Running"
fi

# Check database
if database_exists && table_exists; then
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        FINAL_RECORD_COUNT=$(mysql -u root -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
    else
        FINAL_RECORD_COUNT=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -D "${DB_NAME}" -se "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
    fi
    print_status "Database: OK (${FINAL_RECORD_COUNT} records)"
else
    print_error "Database or table is missing"
    SERVICES_OK=false
fi

# Check API files
if [ -f "$API_DIR/connection.php" ] && [ -f "$API_DIR/api.php" ]; then
    print_status "API files: OK"
else
    print_error "API files are missing"
    SERVICES_OK=false
fi

echo

# Final status
if [ "$SERVICES_OK" = true ]; then
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}   INSTALLATION COMPLETED!      ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
    print_status "All components installed and configured successfully!"
    echo
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}Server IP:${NC} ${SERVER_IP}"
    echo -e "${BLUE}API Endpoint (Local):${NC} http://localhost/api/api.php"
    echo -e "${BLUE}API Endpoint (Remote):${NC} http://${SERVER_IP}/api/api.php"
    echo -e "${BLUE}Secret Key:${NC} ${API_SECRET_KEY}"
    echo -e "${BLUE}Database:${NC} ${DB_NAME} (${FINAL_RECORD_COUNT} sample records)"
    echo -e "${BLUE}Database User:${NC} root (empty password)"
    echo -e "${BLUE}Test Script:${NC} ${API_DIR}/test_api.sh"
    echo
    echo -e "${YELLOW}Quick Test (Local):${NC}"
    echo "curl -X POST http://localhost/api/api.php \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"secret_key\": \"${API_SECRET_KEY}\"}'"
    echo
    echo -e "${YELLOW}Quick Test (Remote):${NC}"
    echo "curl -X POST http://${SERVER_IP}/api/api.php \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"secret_key\": \"${API_SECRET_KEY}\"}'"
    echo
    echo -e "${YELLOW}Run full tests:${NC} bash ${API_DIR}/test_api.sh"
    echo
    
    # Show firewall status
    if command_exists ufw && sudo ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}Firewall Status:${NC}"
        sudo ufw status | grep -E "(Status|80|443)" || true
        echo
    fi
    
    print_status "Installation completed successfully!"
    echo
else
    echo -e "${RED}================================${NC}"
    echo -e "${RED}   INSTALLATION FAILED!         ${NC}"
    echo -e "${RED}================================${NC}"
    echo
    print_error "Some components failed to install properly"
    print_error "Please check the error messages above"
    exit 1
fi