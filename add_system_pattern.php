<?php
// Include database connection
require_once 'connection.php';

echo "Adding SYSTEM message parsing pattern...\n";

try {
    // Insert SYSTEM message pattern
    $patternStmt = $pdo->prepare("INSERT INTO message_patterns (name, description, pattern_regex, priority) VALUES (?, ?, ?, ?)");
    
    $patternStmt->execute([
        'SYSTEM Message Pattern',
        'Matches SYSTEM: messages for system actions and events',
        '/^SYSTEM:\s*(.+)$/',
        15  // Higher priority than existing patterns
    ]);
    
    echo "Added SYSTEM Message Pattern\n";
    
    // Get the pattern ID
    $systemPatternId = $pdo->lastInsertId();
    echo "Pattern ID: $systemPatternId\n";
    
    // Add field extraction rules for SYSTEM pattern
    $fieldRules = [
        ['pattern_id' => $systemPatternId, 'field_name' => 'event_type', 'regex_pattern' => '', 'default_value' => 'system', 'is_required' => 1],
        ['pattern_id' => $systemPatternId, 'field_name' => 'action_description', 'regex_pattern' => '/^SYSTEM:\s*(.+)$/', 'regex_group_index' => 1, 'is_required' => 1]
    ];
    
    $ruleStmt = $pdo->prepare("INSERT INTO field_extraction_rules (pattern_id, field_name, regex_pattern, regex_group_index, default_value, is_required) VALUES (?, ?, ?, ?, ?, ?)");
    
    foreach ($fieldRules as $rule) {
        $ruleStmt->execute([
            $rule['pattern_id'],
            $rule['field_name'],
            $rule['regex_pattern'],
            $rule['regex_group_index'] ?? 1,
            $rule['default_value'] ?? null,
            $rule['is_required']
        ]);
        echo "Added field rule: " . $rule['field_name'] . " for SYSTEM pattern\n";
    }
    
    echo "SYSTEM pattern setup completed!\n";
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
