<?php
/**
 * Standalone encoding self-check for ViscaClient - no network, no camera required.
 * Run with: php test-encode.php
 */

require __DIR__ . '/ViscaClient.php';

$failures = 0;
$checks = 0;

function assertBytes(string $label, array $actual, array $expected): void
{
    global $failures, $checks;
    $checks++;
    if ($actual !== $expected) {
        $failures++;
        echo "FAIL: {$label}\n";
        echo "  expected: " . implode(' ', array_map(fn($b) => sprintf('%02X', $b), $expected)) . "\n";
        echo "  actual:   " . implode(' ', array_map(fn($b) => sprintf('%02X', $b), $actual)) . "\n";
    } else {
        echo "PASS: {$label}\n";
    }
}

$client = new ViscaClient('127.0.0.1', 52381, 'udp', false); // no IP header, so envelope() output is checked directly

// PTZOptics doc: "Home: 81 01 06 04 FF"
assertBytes('panTiltHome', $client->panTiltHome(), [0x81, 0x01, 0x06, 0x04, 0xFF]);

// PTZOptics doc: "pan right + tilt up at speed 12: 81 01 06 01 0C 0C 02 01 FF"
assertBytes('panTilt(12,12,up-right)', $client->panTilt(12, 12, 'up-right'), [0x81, 0x01, 0x06, 0x01, 0x0C, 0x0C, 0x02, 0x01, 0xFF]);

// Zoom stop - identical bytes across PTZOptics/Sony/AVer/Marshall: 81 01 04 07 00 FF
assertBytes('zoomStop', $client->zoomStop(), [0x81, 0x01, 0x04, 0x07, 0x00, 0xFF]);

// Zoom in at speed 5 (variable, nibble 0x2 | speed): 81 01 04 07 25 FF
assertBytes('zoom(5,in)', $client->zoom(5, 'in'), [0x81, 0x01, 0x04, 0x07, 0x25, 0xFF]);

// Power on - identical bytes across Sony/AVer/Marshall: 81 01 04 00 02 FF
assertBytes('power(true)', $client->power(true), [0x81, 0x01, 0x04, 0x00, 0x02, 0xFF]);
assertBytes('power(false)', $client->power(false), [0x81, 0x01, 0x04, 0x00, 0x03, 0xFF]);

// Preset recall: UI preset 1 -> 0-indexed wire value 0: 81 01 04 3F 02 00 FF
assertBytes('presetRecall(1)', $client->presetRecall(1), [0x81, 0x01, 0x04, 0x3F, 0x02, 0x00, 0xFF]);
// UI preset 5 -> wire value 4
assertBytes('presetRecall(5)', $client->presetRecall(5), [0x81, 0x01, 0x04, 0x3F, 0x02, 0x04, 0xFF]);

// VISCA-over-IP header: length must equal actual payload byte count (verified against
// the Marshall module's ViscaSocket.js: payloadLength = payload.length, not a hardcoded value)
$headered = new ViscaClient('127.0.0.1', 52381, 'udp', true);
$payload = [0x81, 0x01, 0x04, 0x00, 0x02, 0xFF]; // 6 bytes
assertBytes('encode() header for 6-byte payload, seq 0', $headered->encode($payload), [
    0x01, 0x00, // payload type: command
    0x00, 0x06, // length = 6
    0x00, 0x00, 0x00, 0x00, // sequence 0
    0x81, 0x01, 0x04, 0x00, 0x02, 0xFF,
]);

echo "\n{$checks} checks run, {$failures} failed.\n";
exit($failures > 0 ? 1 : 0);
