<?php
/**
 * list-captures.php — Returns JSON array of captured images, newest first.
 * Optional GET param: cam — filter to a specific camera number.
 */

header('Content-Type: application/json');

$captureDir = __DIR__ . '/captures';
$cam = isset($_GET['cam']) ? intval($_GET['cam']) : 0;

if (!is_dir($captureDir)) {
    echo json_encode([]);
    exit;
}

$pattern = ($cam > 0)
    ? $captureDir . "/cam{$cam}_*.jpg"
    : $captureDir . '/*.jpg';

$files = glob($pattern);
if ($files === false) {
    echo json_encode([]);
    exit;
}

$captures = [];
foreach ($files as $f) {
    $name = basename($f);
    // Strip cam<N>_ prefix and .jpg, replace underscores with spaces
    $label = preg_replace('/^cam\d+_/', '', $name);
    $label = str_replace('.jpg', '', $label);
    $label = str_replace('_', ' ', $label);

    $captures[] = [
        'filename' => $name,
        'path'     => '/multicamera/captures/' . $name,
        'label'    => $label,
        'modified' => filemtime($f)
    ];
}

usort($captures, function($a, $b) {
    return $b['modified'] - $a['modified'];
});

echo json_encode($captures);
