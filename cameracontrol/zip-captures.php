<?php
/**
 * zip-captures.php — Zips selected capture images and streams the archive.
 *
 * Expects POST with JSON body: { "files": ["filename1.jpg", "filename2.jpg"] }
 * Only serves files from the captures/ directory. Rejects path traversal.
 */

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'POST required']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || empty($input['files']) || !is_array($input['files'])) {
    http_response_code(400);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Missing or invalid "files" array']);
    exit;
}

$captureDir = __DIR__ . '/captures';
$validFiles = [];

foreach ($input['files'] as $name) {
    // Only allow simple filenames — no path separators
    if (!is_string($name) || preg_match('/[\/\\\\]/', $name) || $name === '.' || $name === '..') {
        continue;
    }
    $fullPath = $captureDir . '/' . basename($name);
    if (is_file($fullPath)) {
        $validFiles[] = $fullPath;
    }
}

if (empty($validFiles)) {
    http_response_code(400);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'No valid files found']);
    exit;
}

$tmpZip = tempnam(sys_get_temp_dir(), 'captures_') . '.zip';
$zip = new ZipArchive();
if ($zip->open($tmpZip, ZipArchive::CREATE) !== true) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Failed to create zip archive']);
    exit;
}

foreach ($validFiles as $f) {
    $zip->addFile($f, basename($f));
}
$zip->close();

$zipName = 'captures_' . date('Y-m-d_H-i-s') . '.zip';

header('Content-Type: application/zip');
header('Content-Disposition: attachment; filename="' . $zipName . '"');
header('Content-Length: ' . filesize($tmpZip));

readfile($tmpZip);
unlink($tmpZip);
