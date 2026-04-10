<?php
/**
 * capture-image.php — Captures a still frame from the camera's MJPEG stream
 * and saves it to the captures/ directory at maximum JPEG quality.
 *
 * Returns JSON with the filename and path on success.
 */

header('Content-Type: application/json');

// Only POST allowed
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'POST required']);
    exit;
}

// Camera MJPEG stream — use the local Apache proxy (already configured)
$mjpegUrl = 'http://localhost/mjpeg';

$captureDir = __DIR__ . '/captures';
if (!is_dir($captureDir)) {
    mkdir($captureDir, 0755, true);
}

// Filename: YYYY-MM-DD_HH-MM-SS.jpg
$timestamp = date('Y-m-d_H-i-s');
$filename  = $timestamp . '.jpg';
$absPath   = $captureDir . '/' . $filename;

// Use ffmpeg to grab one frame from the MJPEG stream
// -f mjpeg: force MJPEG input format
// -frames:v 1: capture exactly one frame
// -q:v 1: re-encode at best JPEG quality (1 = highest, range 1-31)
$cmd = sprintf(
    'ffmpeg -f mjpeg -i %s -frames:v 1 -q:v 1 %s 2>&1',
    escapeshellarg($mjpegUrl),
    escapeshellarg($absPath)
);

$output = [];
$exitCode = 0;
exec($cmd, $output, $exitCode);

if ($exitCode !== 0 || !file_exists($absPath)) {
    http_response_code(500);
    echo json_encode([
        'ok'    => false,
        'error' => 'capture failed',
        'detail' => implode("\n", array_slice($output, -5))
    ]);
    exit;
}

$size = filesize($absPath);

echo json_encode([
    'ok'       => true,
    'filename' => $filename,
    'path'     => 'captures/' . $filename,
    'size'     => $size,
    'timestamp' => $timestamp
]);
