<?php
class DeviceManager {
    private $pdo;
    
    public function __construct($pdo) {
        $this->pdo = $pdo;
    }
    
    public function registerDevice($collectorId, $hostname, $port) {
        try {
            // Check if device already exists
            $checkStmt = $this->pdo->prepare("SELECT id, status FROM devices WHERE collector_id = ? AND port = ?");
            $checkStmt->execute([$collectorId, $port]);
            $existingDevice = $checkStmt->fetch(PDO::FETCH_ASSOC);
            
            if ($existingDevice) {
                // Device exists, update device_name and set status to active if needed
                $updateStmt = $this->pdo->prepare("UPDATE devices SET device_name = ?, status = 1, updated_at = NOW() WHERE id = ?");
                $updateStmt->execute([$hostname, $existingDevice['id']]);
                echo "Updated existing device: $hostname (Port: $port)\n";
                return $existingDevice['id'];
            } else {
                // Insert new device
                $insertStmt = $this->pdo->prepare("
                    INSERT INTO devices (collector_id, port, device_name, status, log_quota) 
                    VALUES (?, ?, ?, 1, 10000)
                ");
                $insertStmt->execute([$collectorId, $port, $hostname]);
                $deviceId = $this->pdo->lastInsertId();
                echo "Registered new device: $hostname (Port: $port)\n";
                return $deviceId;
            }
            
        } catch (PDOException $e) {
            echo "Error managing device: " . $e->getMessage() . "\n";
            return false;
        }
    }
    
    public function checkLogQuota($collectorId, $port) {
        try {
            // Get current log count and quota for device
            $stmt = $this->pdo->prepare("
                SELECT d.log_quota, COUNT(lm.id) as current_logs 
                FROM devices d 
                LEFT JOIN log_mirror lm ON lm.port = d.port AND lm.collector_id = d.collector_id 
                WHERE d.collector_id = ? AND d.port = ?
                GROUP BY d.id, d.log_quota
            ");
            $stmt->execute([$collectorId, $port]);
            $result = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if ($result) {
                $quota = $result['log_quota'];
                $currentLogs = $result['current_logs'];
                
                echo "Device quota check - Current: $currentLogs, Quota: $quota\n";
                
                if ($currentLogs >= $quota) {
                    echo "Warning: Device has reached log quota limit!\n";
                    return false;
                }
            }
            
            return true;
            
        } catch (PDOException $e) {
            echo "Error checking quota: " . $e->getMessage() . "\n";
            return true; // Allow logging if check fails
        }
    }
    
    public function getDeviceStats($collectorId = null) {
        try {
            $sql = "
                SELECT d.id, d.device_name, d.port, d.status, d.log_quota,
                       COUNT(lm.id) as total_logs,
                       c.name as collector_name
                FROM devices d
                LEFT JOIN log_mirror lm ON lm.port = d.port AND lm.collector_id = d.collector_id
                LEFT JOIN collectors c ON c.id = d.collector_id
            ";
            
            if ($collectorId) {
                $sql .= " WHERE d.collector_id = ?";
                $stmt = $this->pdo->prepare($sql . " GROUP BY d.id ORDER BY d.device_name");
                $stmt->execute([$collectorId]);
            } else {
                $stmt = $this->pdo->prepare($sql . " GROUP BY d.id ORDER BY d.device_name");
                $stmt->execute();
            }
            
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
            
        } catch (PDOException $e) {
            echo "Error getting device stats: " . $e->getMessage() . "\n";
            return [];
        }
    }
}
?>
