<?php
// Include database connection
require_once 'connection.php';

echo "Setting up field extraction rules...\n";

try {
    // Field extraction rules for File Operations Pattern (ID: 1)
    $fileOpRules = [
        ['pattern_id' => 1, 'field_name' => 'event_type', 'regex_pattern' => '/Event:\s*(\w+)/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => 1, 'field_name' => 'file_path', 'regex_pattern' => '/Path:\s*(.+?)(?:\s*->|,\s*File)/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => 1, 'field_name' => 'destination_path', 'regex_pattern' => '/Path:\s*.+?\s*->\s*(.+?),\s*File/', 'regex_group_index' => 1, 'is_required' => 0],
        ['pattern_id' => 1, 'field_name' => 'file_folder_type', 'regex_pattern' => '/File\/Folder:\s*(\w+)/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => 1, 'field_name' => 'file_size', 'regex_pattern' => '/Size:\s*(.+?),\s*User/', 'regex_group_index' => 1, 'is_required' => 0],
        ['pattern_id' => 1, 'field_name' => 'username', 'regex_pattern' => '/User:\s*(.+?),\s*IP/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => 1, 'field_name' => 'user_ip', 'regex_pattern' => '/IP:\s*(.+)$/', 'regex_group_index' => 1, 'is_required' => 1]
    ];
    
    // Field extraction rules for System Administrative Pattern (ID: 2)
    $adminRules = [
        ['pattern_id' => 2, 'field_name' => 'username', 'regex_pattern' => '/^(.+?):#011/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => 2, 'field_name' => 'admin_action', 'regex_pattern' => '/#011(.+)$/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => 2, 'field_name' => 'event_type', 'regex_pattern' => '', 'regex_group_index' => 1, 'default_value' => 'system_admin', 'is_required' => 0]
    ];
    
    // Combine all rules
    $allRules = array_merge($fileOpRules, $adminRules);
    
    $ruleStmt = $pdo->prepare("INSERT INTO field_extraction_rules (pattern_id, field_name, regex_pattern, regex_group_index, default_value, is_required) VALUES (?, ?, ?, ?, ?, ?)");
    
    foreach ($allRules as $rule) {
        $ruleStmt->execute([
            $rule['pattern_id'],
            $rule['field_name'],
            $rule['regex_pattern'],
            $rule['regex_group_index'],
            $rule['default_value'] ?? null,
            $rule['is_required']
        ]);
        echo "Added field rule: " . $rule['field_name'] . " for pattern " . $rule['pattern_id'] . "\n";
    }
    
    echo "Field extraction rules setup completed!\n";
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
