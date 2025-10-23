#!/bin/bash

# Logger System Automated Installation Script with Activation
# This script installs and configures the complete logger backend system

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PROJECT_DIR="/var/www/html/new-logger-backend"
LOG_DIR="/var/log/logger_system"
DB_NAME="logger_db"
DB_USER="root"

# Activation API configuration
ACTIVATION_API_URL="http://142.91.101.137:3000/api/project_validate"
SECRET_KEY="I3UYA2HSQPB86XpsdVUb9szDu5tn2W3fOpg8"  # Hardcoded secret key

# Global variables for validated data
ACTIVATION_KEY=""
PROJECT_ID=""
COLLECTOR_PORTS=()
LOGGER_IP=""

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

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Get machine IP address
get_machine_ip() {
    # Try to get primary network interface IP
    LOGGER_IP=$(hostname -I | awk '{print $1}')
    
    if [ -z "$LOGGER_IP" ]; then
        print_error "Could not detect machine IP address"
        exit 1
    fi
    
    print_status "Detected Logger IP: $LOGGER_IP"
}

# Get activation key from user
get_activation_key() {
    print_header "ACTIVATION KEY VERIFICATION"
    
    echo -n "Enter your Activation Key (format: XXXX-XXXX-XXXX): "
    read ACTIVATION_KEY
    
    if [ -z "$ACTIVATION_KEY" ]; then
        print_error "Activation key cannot be empty"
        exit 1
    fi
    
    # Basic format validation
    if ! [[ "$ACTIVATION_KEY" =~ ^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]]; then
        print_error "Invalid activation key format. Expected format: XXXX-XXXX-XXXX"
        exit 1
    fi
    
    print_status "Activation key format validated"
}

# Get collector IP from user
get_collector_ip() {
    # Collector IP not needed - removed from workflow
    print_status "Collector IP will be configured later in the system"
}

# Validate activation key with API
validate_activation() {
    print_header "VALIDATING ACTIVATION KEY"
    
    print_status "Contacting activation server at: $ACTIVATION_API_URL"
    print_status "This may take a few seconds..."
    
    # Prepare JSON payload - only sending logger IP
    JSON_PAYLOAD=$(cat <<EOF
{
    "activationKey": "$ACTIVATION_KEY",
    "secretKey": "$SECRET_KEY",
    "loggerIp": "$LOGGER_IP"
}
EOF
)
    
    print_status "Sending activation request..."
    
    # Make API request with timeout
    HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        --connect-timeout 10 \
        --max-time 30 \
        -X POST "$ACTIVATION_API_URL" \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" 2>&1)
    
    CURL_EXIT_CODE=$?
    
    # Check if curl command was successful
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        print_error "Failed to connect to activation server!"
        print_error "Curl exit code: $CURL_EXIT_CODE"
        
        case $CURL_EXIT_CODE in
            6)
                print_error "Could not resolve host. Please check the server address: $ACTIVATION_API_URL"
                ;;
            7)
                print_error "Failed to connect to server. Please check if the server is running and accessible."
                ;;
            28)
                print_error "Connection timeout. The server is not responding."
                ;;
            *)
                print_error "Network error occurred. Please check your internet connection."
                ;;
        esac
        
        echo
        print_error "Installation cannot proceed without activation."
        print_error "Please verify:"
        echo "  1. Activation server is running at: $ACTIVATION_API_URL"
        echo "  2. Network connectivity is working"
        echo "  3. Firewall is not blocking the connection"
        exit 1
    fi
    
    # Extract HTTP status and response body
    HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTP_STATUS\:.*//g')
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    
    print_status "API Response Status: $HTTP_STATUS"
    
    # Check if we got a valid HTTP status
    if [ -z "$HTTP_STATUS" ] || [ "$HTTP_STATUS" = "000" ]; then
        print_error "No valid response from activation server"
        print_error "Response received: $HTTP_RESPONSE"
        echo
        print_error "Installation cannot proceed. Please check server logs."
        exit 1
    fi
    
    # Check HTTP status
    if [ "$HTTP_STATUS" != "200" ]; then
        print_error "Activation failed!"
        echo
        print_error "Response body:"
        echo "$HTTP_BODY" | python3 -m json.tool 2>/dev/null || echo "$HTTP_BODY"
        
        # Parse error message if available
        ERROR_MSG=$(echo "$HTTP_BODY" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        if [ ! -z "$ERROR_MSG" ]; then
            echo
            print_error "Error: $ERROR_MSG"
        fi
        
        echo
        print_error "Installation cannot proceed without valid activation."
        exit 1
    fi
    
    # Parse successful response
    print_success "Activation successful!"
    
    # Extract project ID
    PROJECT_ID=$(echo "$HTTP_BODY" | grep -o '"projectId":[0-9]*' | cut -d':' -f2)
    
    if [ -z "$PROJECT_ID" ]; then
        print_error "Could not extract project ID from response"
        print_error "Response: $HTTP_BODY"
        exit 1
    fi
    
    print_status "Project ID: $PROJECT_ID"
    
    # Extract ports
    PORTS_JSON=$(echo "$HTTP_BODY" | grep -o '"ports":\[[^]]*\]')
    if [ ! -z "$PORTS_JSON" ]; then
        # Parse ports array
        COLLECTOR_PORTS=($(echo "$PORTS_JSON" | grep -o '"port":[0-9]*' | cut -d':' -f2))
        if [ ${#COLLECTOR_PORTS[@]} -gt 0 ]; then
            print_status "Assigned Ports: ${COLLECTOR_PORTS[*]}"
        else
            print_warning "No ports found in response"
        fi
    else
        print_warning "No ports assigned in response"
    fi
    
    echo
    print_success "Activation validated successfully!"
    echo "  Project ID: $PROJECT_ID"
    echo "  Logger IP: $LOGGER_IP"
    echo "  Assigned Ports: ${COLLECTOR_PORTS[*]}"
    echo
}

# Get MySQL password
get_mysql_password() {
    read -s -p "Enter MySQL root password: " MYSQL_PASSWORD
    echo
    if [ -z "$MYSQL_PASSWORD" ]; then
        print_error "MySQL password cannot be empty"
        exit 1
    fi
    
    # Escape special characters in password for sed
    ESCAPED_MYSQL_PASSWORD=$(printf '%s\n' "$MYSQL_PASSWORD" | sed -e 's/[\/&]/\\&/g')
    
    # Debug: Show that we have the password
    print_status "MySQL password captured (length: ${#MYSQL_PASSWORD})"
}

# Fix MySQL authentication
fix_mysql_authentication() {
    print_header "CONFIGURING MYSQL AUTHENTICATION"
    
    print_status "Changing MySQL authentication method to mysql_native_password..."
    
    mysql -u root -p"$MYSQL_PASSWORD" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASSWORD'; FLUSH PRIVILEGES;" 2>/dev/null || {
        print_warning "Could not change authentication method (may already be configured)"
    }
    
    print_status "MySQL authentication configured"
}

# Update system packages
update_system() {
    print_header "UPDATING SYSTEM PACKAGES"
    apt update
    print_status "System packages updated successfully"
}

# Install required packages
install_dependencies() {
    print_header "INSTALLING DEPENDENCIES"
    
    print_status "Installing curl..."
    apt install -y curl
    
    print_status "Installing MySQL Server..."
    apt install -y mysql-server
    
    print_status "Installing PHP and extensions..."
    apt install -y php php-mysql php-cli php-curl php-json
    
    print_status "Installing Apache (if needed)..."
    apt install -y apache2
    
    print_status "Installing Python3 for JSON parsing..."
    apt install -y python3
    
    print_status "Enabling PHP curl extension..."
    # Detect PHP version dynamically
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    PHP_CLI_CONF_DIR="/etc/php/${PHP_VERSION}/cli/conf.d"
    
    if [ -d "$PHP_CLI_CONF_DIR" ]; then
        echo "extension=curl" > "${PHP_CLI_CONF_DIR}/20-curl.ini"
        print_status "PHP curl extension enabled for PHP $PHP_VERSION"
    else
        print_warning "PHP CLI config directory not found, curl extension may already be enabled"
    fi
    
    systemctl restart apache2
    print_status "All dependencies installed successfully"
}

# Create database and tables
setup_database() {
    print_header "SETTING UP DATABASE"
    
    print_status "Creating database and tables..."
    
    # Create SQL file for database setup
    cat > /tmp/logger_db_setup.sql << 'EOF'
-- Create database
CREATE DATABASE IF NOT EXISTS logger_db;
USE logger_db;

-- 1. Collectors table
CREATE TABLE IF NOT EXISTS collectors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    url VARCHAR(500) NOT NULL,
    secret_key VARCHAR(255) NOT NULL,
    last_fetched_id INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    project_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 2. Devices table
CREATE TABLE IF NOT EXISTS devices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    collector_id INT NOT NULL,
    port INT NOT NULL,
    device_name VARCHAR(255) NOT NULL,
    status BOOLEAN DEFAULT 1,
    log_quota INT DEFAULT 10000,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (collector_id) REFERENCES collectors(id) ON DELETE CASCADE,
    UNIQUE KEY unique_collector_port (collector_id, port)
);

-- 3. Log mirror table
CREATE TABLE IF NOT EXISTS log_mirror (
    id INT AUTO_INCREMENT PRIMARY KEY,
    collector_id INT NOT NULL,
    original_log_id INT NOT NULL,
    received_at DATETIME NOT NULL,
    hostname VARCHAR(255),
    facility VARCHAR(100),
    message TEXT,
    port INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (collector_id) REFERENCES collectors(id) ON DELETE CASCADE,
    UNIQUE KEY unique_collector_log (collector_id, original_log_id)
);

-- 4. Message patterns table
CREATE TABLE IF NOT EXISTS message_patterns (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    pattern_regex VARCHAR(1000) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    priority INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 5. Field extraction rules table
CREATE TABLE IF NOT EXISTS field_extraction_rules (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pattern_id INT NOT NULL,
    field_name VARCHAR(100) NOT NULL,
    regex_pattern VARCHAR(500) NOT NULL,
    regex_group_index INT DEFAULT 1,
    default_value VARCHAR(255),
    is_required BOOLEAN DEFAULT FALSE,
    data_type ENUM('string', 'integer', 'float', 'datetime', 'json') DEFAULT 'string',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (pattern_id) REFERENCES message_patterns(id) ON DELETE CASCADE
);

-- 6. Parsed logs table
CREATE TABLE IF NOT EXISTS parsed_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    log_mirror_id INT NOT NULL,
    pattern_id INT,
    event_type VARCHAR(100),
    file_path VARCHAR(1000),
    file_folder_type VARCHAR(50),
    file_size VARCHAR(100),
    username VARCHAR(255),
    user_ip VARCHAR(45),
    source_path VARCHAR(1000),
    destination_path VARCHAR(1000),
    additional_data JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (log_mirror_id) REFERENCES log_mirror(id) ON DELETE CASCADE,
    FOREIGN KEY (pattern_id) REFERENCES message_patterns(id) ON DELETE SET NULL,
    UNIQUE KEY unique_log_pattern (log_mirror_id, pattern_id)
);

-- 7. System actions table
CREATE TABLE IF NOT EXISTS system_actions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    log_id INT NOT NULL,
    collector_id INT NOT NULL,
    action_description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (log_id) REFERENCES log_mirror(id) ON DELETE CASCADE,
    FOREIGN KEY (collector_id) REFERENCES collectors(id) ON DELETE CASCADE
);

-- Insert default message patterns
INSERT IGNORE INTO message_patterns (id, name, description, pattern_regex, priority) VALUES
(1, 'SYSTEM Message Pattern', 'Matches SYSTEM: messages for system actions and events', '/^SYSTEM:\\s*(.+)$/', 15),
(2, 'File Operations Pattern', 'Matches file/folder operations', '/Event:\\s*(\\w+),\\s*Path:\\s*(.+?)(?:\\s*->\\s*(.+?))?,\\s*File\\/Folder:\\s*(\\w+),\\s*Size:\\s*(.+?),\\s*User:\\s*(.+?),\\s*IP:\\s*(.+)$/', 10),
(3, 'System Administrative Pattern', 'Matches system admin messages', '/^(.+?):#011(.+)$/', 5),
(4, 'User Login Pattern', 'Matches user login messages', '/User\\s+\\[(.+?)\\]\\s+from\\s+\\[(.+?)\\]\\s+signed\\s+in\\s+to\\s+\\[(.+?)\\]\\s+successfully\\s+via\\s+\\[(.+?)\\]/', 12),
(5, 'Test Message Pattern', 'Matches test messages', '/Test\\s+message\\s+from\\s+Synology\\s+Syslog\\s+Client\\s+from\\s+\\((.+?)\\)/', 8);

-- Insert field extraction rules
INSERT IGNORE INTO field_extraction_rules (pattern_id, field_name, regex_pattern, regex_group_index, default_value, is_required) VALUES
-- SYSTEM Message Pattern
(1, 'event_type', '', 1, 'system', 1),
(1, 'action_description', '/^SYSTEM:\\s*(.+)$/', 1, NULL, 1),
-- File Operations Pattern
(2, 'event_type', '/Event:\\s*(\\w+)/', 1, NULL, 1),
(2, 'file_path', '/Path:\\s*(.+?)(?:\\s*->|,\\s*File)/', 1, NULL, 1),
(2, 'destination_path', '/Path:\\s*.+?\\s*->\\s*(.+?),\\s*File/', 1, NULL, 0),
(2, 'file_folder_type', '/File\\/Folder:\\s*(\\w+)/', 1, NULL, 1),
(2, 'file_size', '/Size:\\s*(.+?),\\s*User/', 1, NULL, 0),
(2, 'username', '/User:\\s*(.+?),\\s*IP/', 1, NULL, 1),
(2, 'user_ip', '/IP:\\s*(.+)$/', 1, NULL, 1),
-- System Administrative Pattern
(3, 'username', '/^(.+?):#011/', 1, NULL, 1),
(3, 'admin_action', '/#011(.+)$/', 1, NULL, 1),
(3, 'event_type', '', 1, 'system_admin', 0),
-- User Login Pattern
(4, 'event_type', '', 1, 'user_login', 1),
(4, 'username', '/User\\s+\\[(.+?)\\]/', 1, NULL, 1),
(4, 'user_ip', '/from\\s+\\[(.+?)\\]/', 1, NULL, 1),
(4, 'service', '/signed\\s+in\\s+to\\s+\\[(.+?)\\]/', 1, NULL, 0),
(4, 'auth_method', '/via\\s+\\[(.+?)\\]/', 1, NULL, 0),
-- Test Message Pattern
(5, 'event_type', '', 1, 'test_message', 1),
(5, 'source_ip', '/from\\s+\\((.+?)\\)/', 1, NULL, 0);
EOF

    # Execute main SQL file
    mysql -u "$DB_USER" -p"$MYSQL_PASSWORD" < /tmp/logger_db_setup.sql
    
    # Create indexes separately
    print_status "Creating database indexes..."
    cat > /tmp/create_indexes.sql << 'EOF'
USE logger_db;
CREATE INDEX idx_log_mirror_collector ON log_mirror(collector_id);
CREATE INDEX idx_log_mirror_port ON log_mirror(port);
CREATE INDEX idx_log_mirror_hostname ON log_mirror(hostname);
CREATE INDEX idx_log_mirror_received_at ON log_mirror(received_at);
CREATE INDEX idx_parsed_logs_event_type ON parsed_logs(event_type);
CREATE INDEX idx_parsed_logs_username ON parsed_logs(username);
CREATE INDEX idx_system_actions_collector ON system_actions(collector_id);
CREATE INDEX idx_devices_status ON devices(status);
EOF

    mysql -u "$DB_USER" -p"$MYSQL_PASSWORD" < /tmp/create_indexes.sql 2>/dev/null || true
    
    rm /tmp/logger_db_setup.sql /tmp/create_indexes.sql
    
    print_status "Database and tables created successfully"
}

# Setup project files
setup_project_files() {
    print_header "SETTING UP PROJECT FILES"
    
    print_status "Ensuring project directory exists..."
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # Update connection.php with actual password
    if [ -f "connection.php" ]; then
        print_status "Updating database connection..."
        # Show the password length for debugging (without revealing the actual password)
        print_status "Updating connection.php with password (length: ${#ESCAPED_MYSQL_PASSWORD})"
        
        # Use the escaped password to handle special characters
        sed -i "s/\$password = '';/\$password = '$ESCAPED_MYSQL_PASSWORD';/g" connection.php
        
        # Debug: Show the result
        grep "\$password" connection.php | print_status "Updated connection line:"
    fi
    
    # Update log_fetcher_cron.sh path - replace entire cd line
    if [ -f "log_fetcher_cron.sh" ]; then
        print_status "Updating cron script paths..."
        # Replace any cd command with the correct PROJECT_DIR
        sed -i "s|^cd .*|cd $PROJECT_DIR|g" log_fetcher_cron.sh
    fi
    
    print_status "Setting proper file permissions..."
    chown -R www-data:www-data "$PROJECT_DIR"
    chmod -R 755 "$PROJECT_DIR"
    
    if [ -f "$PROJECT_DIR/log_fetcher_cron.sh" ]; then
        chmod +x "$PROJECT_DIR/log_fetcher_cron.sh"
    fi
    
    print_status "Project files configured successfully"
}

# Setup logging directory
setup_logging() {
    print_header "SETTING UP LOGGING"
    
    mkdir -p "$LOG_DIR"
    chown www-data:www-data "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    cat > /etc/logrotate.d/logger-system << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
    
    print_status "Logging setup completed"
}

# Setup cron job
setup_cron() {
    print_header "SETTING UP CRON JOB"
    
    # Remove old cron jobs
    crontab -l 2>/dev/null | grep -v "log_fetcher_cron.sh" | crontab - 2>/dev/null || true
    
    # Add new cron job with correct path
    (crontab -l 2>/dev/null; echo "* * * * * $PROJECT_DIR/log_fetcher_cron.sh") | crontab -
    print_status "Cron job added - will run every minute"
    
    systemctl enable cron
    systemctl start cron
    
    print_status "Cron job setup completed"
}

# Test installation
test_installation() {
    print_header "TESTING INSTALLATION"
    
    print_status "Testing database connection..."
    cd "$PROJECT_DIR"
    
    # First, let's check what's in the connection.php file
    print_status "Checking connection.php content:"
    grep "\$password" connection.php | print_status "  "
    
    if timeout 5 php -r "require 'connection.php'; echo 'Connected\n';" 2>/dev/null; then
        print_success "Database connection test passed"
    else
        print_error "Database connection test failed"
        print_status "Let's test the connection details manually:"
        # Test with PHP to get more detailed error information
        php -r "
        require 'connection.php';
        try {
            \$pdo = new PDO(\"mysql:host=\$host;dbname=\$dbname\", \$username, \$password);
            echo \"Connection successful\n\";
        } catch (PDOException \$e) {
            echo \"Connection failed: \" . \$e->getMessage() . \"\n\";
        }
        " 2>&1 | while read line; do print_error "  \$line"; done
        
        exit 1
    fi
    
    if [ -f "$PROJECT_DIR/log_fetcher_cron.sh" ]; then
        print_status "Testing cron script..."
        timeout 30 bash "$PROJECT_DIR/log_fetcher_cron.sh" || print_warning "Cron script test timed out"
    fi
    
    print_success "Installation tests completed"
}

# Save activation info
save_activation_info() {
    print_header "SAVING ACTIVATION INFO"
    
    cat > "$PROJECT_DIR/.activation_info" << EOF
# Logger Backend Activation Information
# Generated on: $(date)
ACTIVATION_KEY=$ACTIVATION_KEY
PROJECT_ID=$PROJECT_ID
LOGGER_IP=$LOGGER_IP
ASSIGNED_PORTS=${COLLECTOR_PORTS[*]}
EOF
    
    chmod 600 "$PROJECT_DIR/.activation_info"
    print_status "Activation info saved to $PROJECT_DIR/.activation_info"
}

# Display final information
display_info() {
    print_header "INSTALLATION COMPLETED"
    
    echo -e "${GREEN}Logger System has been successfully installed and activated!${NC}"
    echo
    echo "Activation Details:"
    echo "- Activation Key: $ACTIVATION_KEY"
    echo "- Project ID: $PROJECT_ID"
    echo "- Logger IP: $LOGGER_IP"
    echo "- Assigned Ports: ${COLLECTOR_PORTS[*]}"
    echo
    echo "System Configuration:"
    echo "- Project Directory: $PROJECT_DIR"
    echo "- Database Name: $DB_NAME"
    echo "- Log Directory: $LOG_DIR"
    echo "- Cron Job: Running every minute"
    echo
    echo "Next Steps:"
    echo "1. Add your API collectors to the database"
    echo "2. Monitor logs: tail -f $LOG_DIR/log_fetcher.log"
    echo "3. Check errors: tail -f $LOG_DIR/log_fetcher_error.log"
    echo "4. View activation info: cat $PROJECT_DIR/.activation_info"
    echo
}

# Main execution
main() {
    print_header "LOGGER SYSTEM INSTALLER WITH ACTIVATION"
    
    check_root
    
    # Check and install curl if needed
    if ! command -v curl &> /dev/null; then
        print_status "Installing curl for activation validation..."
        apt update -qq
        apt install -y curl > /dev/null 2>&1
        print_status "curl installed successfully"
    else
        print_status "curl is already installed"
    fi
    
    # Check and install python3 if needed
    if ! command -v python3 &> /dev/null; then
        print_status "Installing python3 for JSON parsing..."
        apt install -y python3 > /dev/null 2>&1
        print_status "python3 installed successfully"
    else
        print_status "python3 is already installed"
    fi
    
    get_machine_ip
    get_activation_key
    get_collector_ip
    validate_activation
    
    echo
    read -p "Do you want to proceed with installation? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled by user"
        exit 0
    fi
    
    get_mysql_password
    
    update_system
    install_dependencies
    fix_mysql_authentication
    setup_database
    setup_project_files
    setup_logging
    setup_cron
    test_installation
    save_activation_info
    display_info
    
    print_success "Installation completed successfully!"
}

# Run main function
main "$@"