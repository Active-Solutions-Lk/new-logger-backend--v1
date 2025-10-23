<?php
// Include database connection, message parser, and device manager
require_once '/var/www/html/new-logger-backend--v1/connection.php';
require_once '/var/www/html/new-logger-backend--v1/message_parser.php';
require_once '/var/www/html/new-logger-backend--v1/device_manager.php';

echo "Connected to database successfully\n";

// Initialize message parser and device manager
$parser = new MessageParser($pdo);
$deviceManager = new DeviceManager($pdo);

// Get all active collectors
$stmt = $pdo->prepare("SELECT * FROM collectors WHERE is_active = 1");
$stmt->execute();
$collectors = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "Found " . count($collectors) . " active collector(s)\n";

// Process each collector
foreach ($collectors as $collector) {
    echo "\n=== Processing collector: " . $collector['name'] . " ===\n";

    // Prepare API request
    $postData = json_encode([
        'secret_key' => $collector['secret_key'],
        'last_id' => $collector['last_fetched_id']
    ]);

    // Make API call
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $collector['url']);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode === 200 && $response) {
        $data = json_decode($response, true);
        if ($data && isset($data['success']) && $data['success'] === true) {
            $records = $data['data']['records'];
            echo "API call successful. Records found: " . count($records) . "\n";

            // Insert records into database and parse them
            $insertCount = 0;
            $parseCount = 0;
            $deviceCount = 0;

            $insertStmt = $pdo->prepare("
                INSERT INTO log_mirror (collector_id, original_log_id, received_at, hostname, facility, message, port) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE 
                received_at = VALUES(received_at),
                hostname = VALUES(hostname),
                facility = VALUES(facility),
                message = VALUES(message),
                port = VALUES(port)
            ");

            foreach ($records as $record) {
                try {
                    // Register/update device first
                    $deviceId = $deviceManager->registerDevice($collector['id'], $record['hostname'], $record['port']);
                    if ($deviceId) {
                        $deviceCount++;

                        // Check log quota before inserting
                        if (!$deviceManager->checkLogQuota($collector['id'], $record['port'])) {
                            echo "Skipping log insertion - quota exceeded for device: " . $record['hostname'] . "\n";
                            continue;
                        }
                    }

                    $insertStmt->execute([
                        $collector['id'],
                        $record['id'],
                        $record['received_at'],
                        $record['hostname'],
                        $record['facility'],
                        $record['message'],
                        $record['port']
                    ]);

                    // Get the inserted/updated log_mirror ID
                    $logMirrorId = $pdo->lastInsertId();
                    if (!$logMirrorId) {
                        // If it was an update, get the existing ID
                        $getIdStmt = $pdo->prepare("SELECT id FROM log_mirror WHERE collector_id = ? AND original_log_id = ?");
                        $getIdStmt->execute([$collector['id'], $record['id']]);
                        $logMirrorId = $getIdStmt->fetchColumn();
                    }

                    $insertCount++;

                    // Parse the message
                    if ($parser->parseMessage($record['message'], $logMirrorId, $collector['id'])) {
                        $parseCount++;
                    }
                } catch (PDOException $e) {
                    echo "Error processing record ID " . $record['id'] . ": " . $e->getMessage() . "\n";
                }
            }

            echo "Successfully processed $deviceCount devices\n";
            echo "Successfully inserted/updated $insertCount records\n";
            echo "Successfully parsed $parseCount messages\n";
            echo "Next last_id will be: " . $data['data']['next_last_id'] . "\n";

            // Get next_last_id safely with fallback
            $nextLastId = isset($data['data']['next_last_id']) ? $data['data']['next_last_id'] : $collector['last_fetched_id'];

            echo "Next last_id will be: $nextLastId\n";

            // Update the collector's last_fetched_id
            $updateStmt = $pdo->prepare("UPDATE collectors SET last_fetched_id = ? WHERE id = ?");
            $updateStmt->execute([$nextLastId, $collector['id']]);
            echo "Updated collector's last_fetched_id to: $nextLastId\n";
        } else {
            echo "API call failed or returned error\n";
        }
    } else {
        echo "HTTP request failed. Status code: $httpCode\n";
    }
}

echo "\n=== Processing completed ===\n";
