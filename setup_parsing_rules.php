<?php
// Include database connection
require_once 'connection.php';

echo "Setting up message parsing rules...\n";

try {
    // Insert message patterns
    $patterns = [
        [
            'name' => 'File Operations Pattern',
            'description' => 'Matches file/folder operations like upload, download, delete, rename, move, copy, mkdir',
            'pattern_regex' => '/Event:\s*(\w+),\s*Path:\s*(.+?)(?:\s*->\s*(.+?))?,\s*File\/Folder:\s*(\w+),\s*Size:\s*(.+?),\s*User:\s*(.+?),\s*IP:\s*(.+)$/',
            'priority' => 10
        ],
        [
            'name' => 'System Administrative Pattern',
            'description' => 'Matches system admin messages like user creation, app privileges, etc.',
            'pattern_regex' => '/^(.+?):#011(.+)$/',
            'priority' => 5
        ]
    ];
    
    $patternStmt = $pdo->prepare("INSERT INTO message_patterns (name, description, pattern_regex, priority) VALUES (?, ?, ?, ?)");
    
    foreach ($patterns as $pattern) {
        $patternStmt->execute([
            $pattern['name'],
            $pattern['description'], 
            $pattern['pattern_regex'],
            $pattern['priority']
        ]);
        echo "Added pattern: " . $pattern['name'] . "\n";
    }
    
    // Get pattern IDs for field rules
    $fileOpsPattern = $pdo->query("SELECT id FROM message_patterns WHERE name = 'File Operations Pattern'")->fetch()['id'];
    $adminPattern = $pdo->query("SELECT id FROM message_patterns WHERE name = 'System Administrative Pattern'")->fetch()['id'];
    
    echo "Pattern IDs - File Ops: $fileOpsPattern, Admin: $adminPattern\n";
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
