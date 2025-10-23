<?php
require_once 'system_action_manager.php';

class MessageParser {
    private $pdo;
    private $patterns = [];
    private $fieldRules = [];
    private $systemActionManager;
    
    public function __construct($pdo) {
        $this->pdo = $pdo;
        $this->systemActionManager = new SystemActionManager($pdo);
        $this->loadPatterns();
        $this->loadFieldRules();
    }
    
    private function loadPatterns() {
        $stmt = $this->pdo->prepare("SELECT * FROM message_patterns WHERE is_active = 1 ORDER BY priority DESC");
        $stmt->execute();
        $this->patterns = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    
    private function loadFieldRules() {
        $stmt = $this->pdo->prepare("SELECT * FROM field_extraction_rules ORDER BY pattern_id");
        $stmt->execute();
        $rules = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        foreach ($rules as $rule) {
            $this->fieldRules[$rule['pattern_id']][] = $rule;
        }
    }
    
    public function parseMessage($message, $logMirrorId, $collectorId) {
        $matchedPattern = null;
        $extractedData = [];
        
        // Try to match message against patterns
        foreach ($this->patterns as $pattern) {
            if (preg_match($pattern['pattern_regex'], $message, $matches)) {
                $matchedPattern = $pattern;
                echo "Message matched pattern: " . $pattern['name'] . "\n";
                break;
            }
        }
        
        if (!$matchedPattern) {
            echo "No pattern matched for message: " . substr($message, 0, 100) . "...\n";
            return false;
        }
        
        // Extract fields using field rules
        if (isset($this->fieldRules[$matchedPattern['id']])) {
            foreach ($this->fieldRules[$matchedPattern['id']] as $rule) {
                $value = null;
                
                if (!empty($rule['regex_pattern'])) {
                    if (preg_match($rule['regex_pattern'], $message, $fieldMatches)) {
                        $value = $fieldMatches[$rule['regex_group_index']] ?? null;
                    }
                }
                
                // Use default value if no match and default is set
                if ($value === null && !empty($rule['default_value'])) {
                    $value = $rule['default_value'];
                }
                
                // Check required fields
                if ($rule['is_required'] && empty($value)) {
                    echo "Required field '" . $rule['field_name'] . "' not found\n";
                    return false;
                }
                
                $extractedData[$rule['field_name']] = $value;
            }
        }
        
        // Handle SYSTEM messages specially
        if ($matchedPattern['name'] === 'SYSTEM Message Pattern') {
            return $this->handleSystemMessage($logMirrorId, $collectorId, $extractedData);
        } else {
            // Save regular parsed data
            return $this->saveParsedLog($logMirrorId, $matchedPattern['id'], $extractedData);
        }
    }
    
    private function handleSystemMessage($logMirrorId, $collectorId, $data) {
        // Save to system_actions table
        if (isset($data['action_description'])) {
            $success = $this->systemActionManager->saveSystemAction(
                $logMirrorId, 
                $collectorId, 
                $data['action_description']
            );
            
            if ($success) {
                // Also save to parsed_logs for consistency
                return $this->saveParsedLog($logMirrorId, 3, $data); // Pattern ID 3 is SYSTEM pattern
            }
            return $success;
        }
        
        echo "No action description found in SYSTEM message\n";
        return false;
    }
    
    private function saveParsedLog($logMirrorId, $patternId, $data) {
        try {
            $stmt = $this->pdo->prepare("
                INSERT INTO parsed_logs 
                (log_mirror_id, pattern_id, event_type, file_path, file_folder_type, file_size, username, user_ip, source_path, destination_path, additional_data) 
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                event_type = VALUES(event_type),
                file_path = VALUES(file_path),
                file_folder_type = VALUES(file_folder_type),
                file_size = VALUES(file_size),
                username = VALUES(username),
                user_ip = VALUES(user_ip),
                source_path = VALUES(source_path),
                destination_path = VALUES(destination_path),
                additional_data = VALUES(additional_data)
            ");
            
            // Handle additional data for fields not in main columns
            $additionalData = [];
            $mainFields = ['event_type', 'file_path', 'file_folder_type', 'file_size', 'username', 'user_ip'];
            
            foreach ($data as $key => $value) {
                if (!in_array($key, $mainFields)) {
                    $additionalData[$key] = $value;
                }
            }
            
            $stmt->execute([
                $logMirrorId,
                $patternId,
                $data['event_type'] ?? null,
                $data['file_path'] ?? null,
                $data['file_folder_type'] ?? null,
                $data['file_size'] ?? null,
                $data['username'] ?? null,
                $data['user_ip'] ?? null,
                $data['file_path'] ?? null, // source_path
                $data['destination_path'] ?? null,
                json_encode($additionalData)
            ]);
            
            echo "Parsed log saved successfully\n";
            return true;
            
        } catch (Exception $e) {
            echo "Error saving parsed log: " . $e->getMessage() . "\n";
            return false;
        }
    }
}
?>
