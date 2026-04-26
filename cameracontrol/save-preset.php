<?php
/**
 * save-preset.php — Saves a camera preset thumbnail and updates presets.json.
 *
 * Expects a POST with:
 *   - number    (int, 1-100)
 *   - label     (string, preset name)
 *   - thumbnail (file upload, JPEG image — optional)
 *
 * On success: saves thumbnail to images/preset{N}.jpg and
 * adds/updates the entry in presets.json.
 */

const MAX_THUMBNAIL_BYTES = 5 * 1024 * 1024; // 5 MB

header('Content-Type: application/json');

// Only POST allowed
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'POST required']);
    exit;
}

$number = isset($_POST['number']) ? intval($_POST['number']) : 0;
$label  = isset($_POST['label'])  ? trim($_POST['label'])    : '';

// Validate
if ($number < 1 || $number > 100) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Preset number must be 1-100']);
    exit;
}
if ($label === '') {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Preset label is required']);
    exit;
}

$imagesDir  = __DIR__ . '/images';
$presetsFile = __DIR__ . '/presets.json';
$imagePath  = 'images/preset' . $number . '.jpg';
$absImage   = $imagesDir . '/preset' . $number . '.jpg';

// Save uploaded thumbnail if present
$thumbnailSaved = false;
if (isset($_FILES['thumbnail']) && $_FILES['thumbnail']['error'] === UPLOAD_ERR_OK) {
    $tmpPath = $_FILES['thumbnail']['tmp_name'];

    // Reject files larger than the configured limit
    if ($_FILES['thumbnail']['size'] > MAX_THUMBNAIL_BYTES) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Thumbnail must be smaller than 5 MB']);
        exit;
    }

    // Verify it's actually a JPEG image
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime  = finfo_file($finfo, $tmpPath);
    finfo_close($finfo);

    if (!in_array($mime, ['image/jpeg', 'image/jpg'], true)) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Thumbnail must be a JPEG image']);
        exit;
    }

    if (!is_dir($imagesDir)) {
        mkdir($imagesDir, 0755, true);
    }

    if (!move_uploaded_file($tmpPath, $absImage)) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Failed to save thumbnail']);
        exit;
    }
    $thumbnailSaved = true;
} else {
    // No thumbnail uploaded — use existing or fallback
    if (!file_exists($absImage)) {
        $imagePath = 'images/none.jpg';
    }
}

// Load presets.json
$presets = [];
if (file_exists($presetsFile)) {
    $raw = file_get_contents($presetsFile);
    $presets = json_decode($raw, true);
    if (!is_array($presets)) {
        $presets = [];
    }
}

$overwrite = isset($_POST['overwrite']) && $_POST['overwrite'] === '1';

// Check if preset number already exists
$existingIdx = null;
foreach ($presets as $idx => $p) {
    if (isset($p['number']) && intval($p['number']) === $number) {
        $existingIdx = $idx;
        break;
    }
}

if ($existingIdx !== null && !$overwrite) {
    http_response_code(409);
    echo json_encode(['ok' => false, 'error' => 'Preset ' . $number . ' already exists ("' . $presets[$existingIdx]['label'] . '"). Cannot overwrite.']);
    exit;
}

// Add cache-busting parameter when thumbnail was replaced;
// preserve any existing version string when only the label is being updated.
$imagePathForJson = $imagePath;
if ($thumbnailSaved) {
    $imagePathForJson = $imagePath . '?v=' . time();
} elseif ($existingIdx !== null && isset($presets[$existingIdx]['image'])) {
    $imagePathForJson = $presets[$existingIdx]['image'];
}

if ($existingIdx !== null) {
    // Overwrite existing entry
    $presets[$existingIdx] = [
        'number' => $number,
        'label'  => $label,
        'image'  => $imagePathForJson,
    ];
} else {
    $presets[] = [
        'number' => $number,
        'label'  => $label,
        'image'  => $imagePathForJson,
    ];
}

// Sort by preset number
usort($presets, function($a, $b) {
    return intval($a['number']) - intval($b['number']);
});

// Write back
$json = json_encode($presets, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
if (file_put_contents($presetsFile, $json) === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Failed to write presets.json']);
    exit;
}

echo json_encode(['ok' => true, 'preset' => $number, 'label' => $label, 'image' => $imagePathForJson]);
