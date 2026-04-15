<?php
/**
 * onvif-proxy.php — ONVIF camera proxy for the multicamera system
 *
 * Translates simple HTTP requests into ONVIF SOAP calls with WS-Security
 * authentication. Handles PTZ control, preset management, and snapshot proxying.
 *
 * Actions (GET):
 *   ?action=snapshot&cam=N           — Proxy a single JPEG snapshot
 *   ?action=getPresets&cam=N         — List camera presets as JSON
 *
 * Actions (POST):
 *   action=gotoPreset&cam=N&preset=TOKEN  — Recall a preset
 *   action=move&cam=N&pan=X&tilt=Y&zoom=Z — Continuous PTZ move (-1.0 to 1.0)
 *   action=stop&cam=N                     — Stop PTZ movement
 */

// ---- LOAD CONFIG ----

$camerasFile = __DIR__ . '/config/cameras.json';
$camerasData = json_decode(file_get_contents($camerasFile), true);
$cameras = $camerasData['cameras'] ?? [];

$credsFile = __DIR__ . '/config/onvif-credentials.php';
$credentials = file_exists($credsFile) ? (require $credsFile) : [];

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$camNum = $_GET['cam'] ?? $_POST['cam'] ?? '';

// ---- RESOLVE CAMERA ----

$camCfg = $cameras[$camNum] ?? null;
if (!$camCfg) {
    http_response_code(404);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'Camera not found']);
    exit;
}

// Normalize: plain IP string → panasonic object
if (is_string($camCfg)) {
    $camCfg = ['ip' => $camCfg, 'type' => 'panasonic'];
}

if (($camCfg['type'] ?? 'panasonic') !== 'onvif') {
    http_response_code(400);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'Camera is not ONVIF type']);
    exit;
}

$ip = $camCfg['ip'];
if (!filter_var($ip, FILTER_VALIDATE_IP)) {
    http_response_code(400);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'Invalid camera IP']);
    exit;
}

$creds = $credentials[$camNum] ?? [];
$user = $creds['user'] ?? 'admin';
$pass = $creds['pass'] ?? '';
$snapshotPath = $creds['snapshot'] ?? '/onvif-http/snapshot';
$profileToken = $creds['profile'] ?? 'Profile_1';

// ---- DISPATCH ----

switch ($action) {
    case 'snapshot':
        proxySnapshot($ip, $snapshotPath, $user, $pass);
        break;
    case 'getPresets':
        getPresets($ip, $user, $pass, $profileToken);
        break;
    case 'gotoPreset':
        $preset = $_POST['preset'] ?? $_GET['preset'] ?? '';
        gotoPreset($ip, $user, $pass, $profileToken, $preset);
        break;
    case 'move':
        $pan  = max(-1, min(1, floatval($_POST['pan']  ?? 0)));
        $tilt = max(-1, min(1, floatval($_POST['tilt'] ?? 0)));
        $zoom = max(-1, min(1, floatval($_POST['zoom'] ?? 0)));
        continuousMove($ip, $user, $pass, $profileToken, $pan, $tilt, $zoom);
        break;
    case 'stop':
        stopMove($ip, $user, $pass, $profileToken);
        break;
    default:
        http_response_code(400);
        header('Content-Type: application/json');
        echo json_encode(['ok' => false, 'error' => 'Unknown action']);
        exit;
}

// ============================================================
// WS-SECURITY AUTHENTICATION
// ============================================================

function wsseHeader($user, $pass) {
    $nonce   = random_bytes(16);
    $created = gmdate('Y-m-d\TH:i:s\Z');
    $digest  = base64_encode(sha1($nonce . $created . $pass, true));
    $nonceB64 = base64_encode($nonce);

    return <<<XML
    <s:Header>
      <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                     xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
        <wsse:UsernameToken>
          <wsse:Username>{$user}</wsse:Username>
          <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">{$digest}</wsse:Password>
          <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">{$nonceB64}</wsse:Nonce>
          <wsu:Created>{$created}</wsu:Created>
        </wsse:UsernameToken>
      </wsse:Security>
    </s:Header>
XML;
}

function soapRequest($ip, $service, $soapBody, $user, $pass) {
    $url = "http://{$ip}/onvif/{$service}";
    $header = wsseHeader($user, $pass);

    $envelope = <<<XML
<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
            xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl"
            xmlns:tt="http://www.onvif.org/ver10/schema"
            xmlns:trt="http://www.onvif.org/ver10/media/wsdl">
{$header}
    <s:Body>
{$soapBody}
    </s:Body>
</s:Envelope>
XML;

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $envelope,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/soap+xml; charset=utf-8',
            'Content-Length: ' . strlen($envelope),
        ],
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT        => 10,
    ]);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error    = curl_error($ch);
    curl_close($ch);

    if ($error) {
        return ['ok' => false, 'error' => "cURL: {$error}"];
    }
    if ($httpCode >= 400) {
        return ['ok' => false, 'error' => "HTTP {$httpCode}", 'response' => $response];
    }

    return ['ok' => true, 'response' => $response];
}

// ============================================================
// SNAPSHOT PROXY
// ============================================================

function proxySnapshot($ip, $snapshotPath, $user, $pass) {
    $url = "http://{$ip}{$snapshotPath}";

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPAUTH       => CURLAUTH_DIGEST | CURLAUTH_BASIC,
        CURLOPT_USERPWD        => "{$user}:{$pass}",
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT        => 10,
    ]);

    $data        = curl_exec($ch);
    $contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
    $httpCode    = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error       = curl_error($ch);
    curl_close($ch);

    if ($httpCode !== 200 || !$data) {
        http_response_code(502);
        header('Content-Type: application/json');
        echo json_encode(['ok' => false, 'error' => 'Snapshot failed', 'detail' => $error]);
        return;
    }

    header('Content-Type: ' . ($contentType ?: 'image/jpeg'));
    header('Cache-Control: no-cache, no-store');
    header('Content-Length: ' . strlen($data));
    echo $data;
}

// ============================================================
// PTZ — GET PRESETS
// ============================================================

function getPresets($ip, $user, $pass, $profileToken) {
    header('Content-Type: application/json');

    $body = <<<XML
        <tptz:GetPresets>
            <tptz:ProfileToken>{$profileToken}</tptz:ProfileToken>
        </tptz:GetPresets>
XML;

    $result = soapRequest($ip, 'ptz_service', $body, $user, $pass);

    if (!$result['ok']) {
        http_response_code(502);
        echo json_encode($result);
        return;
    }

    // Parse presets from SOAP response
    $xml = @simplexml_load_string($result['response']);
    if (!$xml) {
        http_response_code(502);
        echo json_encode(['ok' => false, 'error' => 'Failed to parse ONVIF response']);
        return;
    }

    $xml->registerXPathNamespace('tptz', 'http://www.onvif.org/ver20/ptz/wsdl');
    $xml->registerXPathNamespace('tt', 'http://www.onvif.org/ver10/schema');

    $presetNodes = $xml->xpath('//tptz:Preset');
    $presets = [];

    foreach ($presetNodes as $node) {
        $token = (string)$node['token'];
        $name  = (string)$node->children('http://www.onvif.org/ver10/schema')->Name;
        if (!$name) {
            $name = (string)$node->Name;
        }
        $presets[] = [
            'token' => $token,
            'name'  => $name ?: "Preset {$token}",
        ];
    }

    echo json_encode(['ok' => true, 'presets' => $presets]);
}

// ============================================================
// PTZ — GOTO PRESET
// ============================================================

function gotoPreset($ip, $user, $pass, $profileToken, $preset) {
    header('Content-Type: application/json');

    if ($preset === '') {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Preset token required']);
        return;
    }

    $presetSafe = htmlspecialchars($preset, ENT_XML1);

    $body = <<<XML
        <tptz:GotoPreset>
            <tptz:ProfileToken>{$profileToken}</tptz:ProfileToken>
            <tptz:PresetToken>{$presetSafe}</tptz:PresetToken>
            <tptz:Speed>
                <tt:PanTilt x="1" y="1"/>
                <tt:Zoom x="1"/>
            </tptz:Speed>
        </tptz:GotoPreset>
XML;

    $result = soapRequest($ip, 'ptz_service', $body, $user, $pass);
    echo json_encode($result);
}

// ============================================================
// PTZ — CONTINUOUS MOVE
// ============================================================

function continuousMove($ip, $user, $pass, $profileToken, $pan, $tilt, $zoom) {
    header('Content-Type: application/json');

    $body = <<<XML
        <tptz:ContinuousMove>
            <tptz:ProfileToken>{$profileToken}</tptz:ProfileToken>
            <tptz:Velocity>
                <tt:PanTilt x="{$pan}" y="{$tilt}"/>
                <tt:Zoom x="{$zoom}"/>
            </tptz:Velocity>
        </tptz:ContinuousMove>
XML;

    $result = soapRequest($ip, 'ptz_service', $body, $user, $pass);
    echo json_encode($result);
}

// ============================================================
// PTZ — STOP
// ============================================================

function stopMove($ip, $user, $pass, $profileToken) {
    header('Content-Type: application/json');

    $body = <<<XML
        <tptz:Stop>
            <tptz:ProfileToken>{$profileToken}</tptz:ProfileToken>
            <tptz:PanTilt>true</tptz:PanTilt>
            <tptz:Zoom>true</tptz:Zoom>
        </tptz:Stop>
XML;

    $result = soapRequest($ip, 'ptz_service', $body, $user, $pass);
    echo json_encode($result);
}
