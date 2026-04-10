<?php
/**
 * capture-image.php — Captures a high-quality still frame from the camera's
 * RTSP stream via ffmpeg and saves it to the captures/ directory.
 *
 * Returns JSON with the filename and path on success.
 * Requires ffmpeg installed on the server.
 */

header('Content-Type: application/json');

// Only POST allowed
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'POST required']);
    exit;
}

// Camera RTSP URL — full quality H.264 stream
$rtspUrl = 'rtsp://172.25.0.200/MediaInput/h264/stream_1';

$captureDir = __DIR__ . '/captures';
if (!is_dir($captureDir)) {
    mkdir($captureDir, 0755, true);
}

// Filename: YYYY-MM-DD_HH-MM-SS.jpg (colons not safe in filenames)
$timestamp = date('Y-m-d_H-i-s');
$filename  = $timestamp . '.jpg';
$absPath   = $captureDir . '/' . $filename;

// Grab a single frame from the RTSP stream at full resolution
// -rtsp_transport tcp: more reliable than UDP on local networks
// -frames:v 1: capture exactly one frame
// -q:v 2: highest JPEG quality (2 = near lossless, range 2-31)
$cmd = sprintf(
    'ffmpeg -rtsp_transport tcp -i %s -frames:v 1 -q:v 2 %s 2>&1',
    escapeshellarg($rtspUrl),
    escapeshellarg($absPath)
);

$output = [];
$exitCode = 0;
exec($cmd, $output, $exitCode);

if ($exitCode !== 0 || !file_exists($absPath)) {
    http_response_code(500);
    echo json_encode([
        'ok'    => false,
        'error' => 'ffmpeg capture failed',
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
