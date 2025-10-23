<?php
// Database configuration
$host = 'localhost';
$dbname = 'logger_db';
$username = 'root';
$password = ''; // Replace with your actual MySQL password

try {
    // Create PDO connection
    $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
} catch (PDOException $e) {
    die("Database connection failed: " . $e->getMessage() . "\n");
}
?>
