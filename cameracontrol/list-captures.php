<?php
/**
 * list-captures.php — Returns a JSON array of captured images, newest first.
 */

header('Content-Type: application/json');

$captureDir = __DIR__ . '/captures';

if (!is_dir($captureDir)) {
    echo json_encode([]);
    exit;
}

$files = glob($captureDir . '/*.jpg');
if ($files === false) {
    echo json_encode([]);
    exit;
}

$captures = [];
foreach ($files as $f) {
    $name = basename($f);
    $captures[] = [
        'filename' => $name,
        'path'     => 'captures/' . $name,
        'size'     => filesize($f),
        'modified' => filemtime($f)
    ];
}

// Sort newest first
usort($captures, function($a, $b) {
    return $b['modified'] - $a['modified'];
});

echo json_encode($captures);
