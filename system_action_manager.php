<?php
class SystemActionManager {
    private $pdo;
    
    public function __construct($pdo) {
        $this->pdo = $pdo;
    }
    
    public function saveSystemAction($logMirrorId, $collectorId, $actionDescription) {
        try {
            // Check if system action already exists for this log
            $checkStmt = $this->pdo->prepare("SELECT id FROM system_actions WHERE log_id = ?");
            $checkStmt->execute([$logMirrorId]);
            
            if ($checkStmt->fetch()) {
                echo "System action already exists for log ID: $logMirrorId\n";
                return true;
            }
            
            // Insert new system action
            $insertStmt = $this->pdo->prepare("
                INSERT INTO system_actions (log_id, collector_id, action_description) 
                VALUES (?, ?, ?)
            ");
            
            $insertStmt->execute([$logMirrorId, $collectorId, $actionDescription]);
            
            echo "System action saved: " . substr($actionDescription, 0, 50) . "...\n";
            return true;
            
        } catch (PDOException $e) {
            echo "Error saving system action: " . $e->getMessage() . "\n";
            return false;
        }
    }
    
    public function getSystemActions($collectorId = null, $limit = 100) {
        try {
            $sql = "
                SELECT sa.*, lm.hostname, lm.received_at, c.name as collector_name
                FROM system_actions sa
                JOIN log_mirror lm ON sa.log_id = lm.id
                JOIN collectors c ON sa.collector_id = c.id
            ";
            
            if ($collectorId) {
                $sql .= " WHERE sa.collector_id = ?";
                $sql .= " ORDER BY sa.created_at DESC LIMIT ?";
                $stmt = $this->pdo->prepare($sql);
                $stmt->execute([$collectorId, $limit]);
            } else {
                $sql .= " ORDER BY sa.created_at DESC LIMIT ?";
                $stmt = $this->pdo->prepare($sql);
                $stmt->execute([$limit]);
            }
            
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
            
        } catch (PDOException $e) {
            echo "Error getting system actions: " . $e->getMessage() . "\n";
            return [];
        }
    }
    
    public function getSystemActionStats($collectorId = null) {
        try {
            $sql = "
                SELECT 
                    COUNT(*) as total_actions,
                    DATE(created_at) as action_date,
                    c.name as collector_name
                FROM system_actions sa
                JOIN collectors c ON sa.collector_id = c.id
            ";
            
            if ($collectorId) {
                $sql .= " WHERE sa.collector_id = ?";
                $sql .= " GROUP BY DATE(created_at), c.name ORDER BY action_date DESC";
                $stmt = $this->pdo->prepare($sql);
                $stmt->execute([$collectorId]);
            } else {
                $sql .= " GROUP BY DATE(created_at), c.name ORDER BY action_date DESC";
                $stmt = $this->pdo->prepare($sql);
                $stmt->execute();
            }
            
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
            
        } catch (PDOException $e) {
            echo "Error getting system action stats: " . $e->getMessage() . "\n";
            return [];
        }
    }
}
?>
