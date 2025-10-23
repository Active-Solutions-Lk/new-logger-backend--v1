<?php
// Include database connection
require_once 'connection.php';

echo "Setting up collector...\n";

try {
    // Check if collectors table exists
    $stmt = $pdo->prepare("SHOW TABLES LIKE 'collectors'");
    $stmt->execute();
    $tableExists = $stmt->fetch();
    
    if (!$tableExists) {
        echo "Creating collectors table...\n";
        $pdo->exec("
            CREATE TABLE collectors (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                url VARCHAR(500) NOT NULL,
                secret_key VARCHAR(100) NOT NULL,
                last_fetched_id INT DEFAULT 0,
                is_active TINYINT(1) DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ");
        echo "Collectors table created.\n";
    }
    
    // Check if log_mirror table exists
    $stmt = $pdo->prepare("SHOW TABLES LIKE 'log_mirror'");
    $stmt->execute();
    $tableExists = $stmt->fetch();
    
    if (!$tableExists) {
        echo "Creating log_mirror table...\n";
        $pdo->exec("
            CREATE TABLE log_mirror (
                id INT AUTO_INCREMENT PRIMARY KEY,
                collector_id INT NOT NULL,
                original_log_id INT NOT NULL,
                received_at DATETIME NULL,
                hostname VARCHAR(255) NULL,
                facility VARCHAR(50) NULL,
                message TEXT NULL,
                port INT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_log (collector_id, original_log_id),
                INDEX idx_collector_id (collector_id),
                INDEX idx_received_at (received_at),
                INDEX idx_hostname (hostname)
            )
        ");
        echo "Log mirror table created.\n";
    }
    
    // Check if parsed_logs table exists
    $stmt = $pdo->prepare("SHOW TABLES LIKE 'parsed_logs'");
    $stmt->execute();
    $tableExists = $stmt->fetch();
    
    if (!$tableExists) {
        echo "Creating parsed_logs table...\n";
        $pdo->exec("
            CREATE TABLE parsed_logs (
                id INT AUTO_INCREMENT PRIMARY KEY,
                log_mirror_id INT NOT NULL,
                collector_id INT NOT NULL,
                timestamp DATETIME NULL,
                source_ip VARCHAR(45) NULL,
                user VARCHAR(100) NULL,
                action VARCHAR(100) NULL,
                target VARCHAR(255) NULL,
                service VARCHAR(100) NULL,
                status VARCHAR(50) NULL,
                details TEXT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_log_mirror_id (log_mirror_id),
                INDEX idx_collector_id (collector_id),
                INDEX idx_timestamp (timestamp),
                INDEX idx_user (user),
                INDEX idx_action (action)
            )
        ");
        echo "Parsed logs table created.\n";
    }
    
    // Check if devices table exists
    $stmt = $pdo->prepare("SHOW TABLES LIKE 'devices'");
    $stmt->execute();
    $tableExists = $stmt->fetch();
    
    if (!$tableExists) {
        echo "Creating devices table...\n";
        $pdo->exec("
            CREATE TABLE devices (
                id INT AUTO_INCREMENT PRIMARY KEY,
                collector_id INT NOT NULL,
                hostname VARCHAR(255) NOT NULL,
                ip_address VARCHAR(45) NULL,
                port INT NULL,
                first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                log_count INT DEFAULT 0,
                UNIQUE KEY unique_device (collector_id, hostname, port),
                INDEX idx_collector_id (collector_id),
                INDEX idx_hostname (hostname)
            )
        ");
        echo "Devices table created.\n";
    }
    
    // Add a default collector for testing
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM collectors");
    $stmt->execute();
    $count = $stmt->fetchColumn();
    
    if ($count == 0) {
        echo "Adding default collector...\n";
        $insertStmt = $pdo->prepare("
            INSERT INTO collectors (name, url, secret_key, last_fetched_id, is_active) 
            VALUES (?, ?, ?, ?, ?)
        ");
        $insertStmt->execute([
            'Local API Collector',
            'http://localhost/api/api.php',
            'sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d',
            0,
            1
        ]);
        echo "Default collector added.\n";
    } else {
        echo "Collector already exists.\n";
    }
    
    echo "Setup completed successfully.\n";
    
} catch (PDOException $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>