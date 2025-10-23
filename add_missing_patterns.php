<?php
// Include database connection
require_once 'connection.php';

echo "Adding missing message parsing patterns...\n";

try {
    // Add User Login Pattern
    $patternStmt = $pdo->prepare("INSERT INTO message_patterns (name, description, pattern_regex, priority) VALUES (?, ?, ?, ?)");
    
    // User Login Pattern
    $patternStmt->execute([
        'User Login Pattern',
        'Matches user login/authentication messages',
        '/User\s+\[(.+?)\]\s+from\s+\[(.+?)\]\s+signed\s+in\s+to\s+\[(.+?)\]\s+successfully\s+via\s+\[(.+?)\]/',
        12
    ]);
    echo "Added User Login Pattern\n";
    $loginPatternId = $pdo->lastInsertId();
    
    // Test Message Pattern
    $patternStmt->execute([
        'Test Message Pattern', 
        'Matches test messages from Synology Syslog Client',
        '/Test\s+message\s+from\s+Synology\s+Syslog\s+Client\s+from\s+\((.+?)\)/',
        8
    ]);
    echo "Added Test Message Pattern\n";
    $testPatternId = $pdo->lastInsertId();
    
    // Add field extraction rules for User Login Pattern
    $loginRules = [
        ['pattern_id' => $loginPatternId, 'field_name' => 'event_type', 'regex_pattern' => '', 'default_value' => 'user_login', 'is_required' => 1],
        ['pattern_id' => $loginPatternId, 'field_name' => 'username', 'regex_pattern' => '/User\s+\[(.+?)\]/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => $loginPatternId, 'field_name' => 'user_ip', 'regex_pattern' => '/from\s+\[(.+?)\]/', 'regex_group_index' => 1, 'is_required' => 1],
        ['pattern_id' => $loginPatternId, 'field_name' => 'service', 'regex_pattern' => '/signed\s+in\s+to\s+\[(.+?)\]/', 'regex_group_index' => 1, 'is_required' => 0],
        ['pattern_id' => $loginPatternId, 'field_name' => 'auth_method', 'regex_pattern' => '/via\s+\[(.+?)\]/', 'regex_group_index' => 1, 'is_required' => 0]
    ];
    
    // Add field extraction rules for Test Message Pattern
    $testRules = [
        ['pattern_id' => $testPatternId, 'field_name' => 'event_type', 'regex_pattern' => '', 'default_value' => 'test_message', 'is_required' => 1],
        ['pattern_id' => $testPatternId, 'field_name' => 'source_ip', 'regex_pattern' => '/from\s+\((.+?)\)/', 'regex_group_index' => 1, 'is_required' => 0]
    ];
    
    // Combine all rules
    $allRules = array_merge($loginRules, $testRules);
    
    $ruleStmt = $pdo->prepare("INSERT INTO field_extraction_rules (pattern_id, field_name, regex_pattern, regex_group_index, default_value, is_required) VALUES (?, ?, ?, ?, ?, ?)");
    
    foreach ($allRules as $rule) {
        $ruleStmt->execute([
            $rule['pattern_id'],
            $rule['field_name'],
            $rule['regex_pattern'],
            $rule['regex_group_index'] ?? 1,
            $rule['default_value'] ?? null,
            $rule['is_required']
        ]);
        echo "Added field rule: " . $rule['field_name'] . " for pattern " . $rule['pattern_id'] . "\n";
    }
    
    echo "Missing patterns setup completed!\n";
    echo "Login Pattern ID: $loginPatternId\n";
    echo "Test Pattern ID: $testPatternId\n";
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
