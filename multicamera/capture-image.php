<?php
/**
 * capture-image.php — Captures a still frame from a camera's MJPEG stream
 * and saves it to the captures/ directory at maximum JPEG quality.
 *
 * Required POST parameters:
 *   cam  — camera number (e.g. 1, 2, 3, 4)
 *   ip   — camera IP address (e.g. 172.25.0.200)
 *
 * Returns JSON with the filename and path on success.
 */

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'POST required']);
    exit;
}

$cam = isset($_POST['cam']) ? intval($_POST['cam']) : 0;
$ip  = isset($_POST['ip'])  ? $_POST['ip']         : '';
$type = isset($_POST['type']) ? $_POST['type']      : 'panasonic';

// Validate camera number
if ($cam < 1 || $cam > 99) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid camera number']);
    exit;
}

// Validate IP address
if (!filter_var($ip, FILTER_VALIDATE_IP)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid IP address']);
    exit;
}

// Validate type
if (!in_array($type, ['panasonic', 'onvif'], true)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid camera type']);
    exit;
}

$captureDir = __DIR__ . '/captures';
if (!is_dir($captureDir)) {
    mkdir($captureDir, 0755, true);
}

// Filename: cam<N>_YYYY-MM-DD_HH-MM-SS.jpg
$timestamp = date('Y-m-d_H-i-s');
$filename  = "cam{$cam}_{$timestamp}.jpg";
$absPath   = $captureDir . '/' . $filename;

if ($type === 'onvif') {
    // ONVIF — fetch snapshot via onvif-proxy (handles auth internally)
    $snapshotUrl = "http://localhost/multicamera/onvif-proxy.php?action=snapshot&cam={$cam}";
    $ch = curl_init($snapshotUrl);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT        => 10,
    ]);
    $data = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($httpCode !== 200 || !$data) {
        http_response_code(500);
        echo json_encode([
            'ok'     => false,
            'error'  => 'ONVIF snapshot failed',
            'detail' => $error
        ]);
        exit;
    }

    file_put_contents($absPath, $data);
} else {
    // Panasonic — grab frame from MJPEG stream via ffmpeg
    $mjpegUrl = "http://{$ip}/cgi-bin/mjpeg?resolution=1920x1080&framerate=5&quality=1";
    $cmd = sprintf(
        'ffmpeg -y -timeout 10000000 -f mjpeg -i %s -frames:v 1 -q:v 1 %s 2>&1',
        escapeshellarg($mjpegUrl),
        escapeshellarg($absPath)
    );

    $output = [];
    $exitCode = 0;
    exec($cmd, $output, $exitCode);

    if ($exitCode !== 0 || !file_exists($absPath)) {
        http_response_code(500);
        echo json_encode([
            'ok'     => false,
            'error'  => 'capture failed',
            'detail' => implode("\n", array_slice($output, -5))
        ]);
        exit;
    }
}

$size = filesize($absPath);

echo json_encode([
    'ok'        => true,
    'filename'  => $filename,
    'path'      => 'captures/' . $filename,
    'size'      => $size,
    'cam'       => $cam,
    'timestamp' => $timestamp
]);
