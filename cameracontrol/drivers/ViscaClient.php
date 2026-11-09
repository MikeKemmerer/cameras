<?php
/**
 * ViscaClient - minimal VISCA / VISCA-over-IP command encoder + socket client.
 *
 * This is a STANDALONE, ADDITIVE library. Nothing in cameracontrol/ currently
 * requires or includes this file - index.htm, ptz-control.htm, and the
 * Apache /cam/ptz + /cam/cam proxy routes for the AW-HE40 are completely
 * unmodified and unaffected by its presence. See README.md in this folder.
 *
 * Command byte tables below are cross-checked against the *-VISCA-API-REFERENCE.md
 * docs one directory up (PTZOptics, Sony, AVer, Marshall all share this core
 * VISCA vocabulary - see those docs for brand-specific extras and caveats).
 */

class ViscaClient
{
    private string $host;
    private int $port;
    /** 'udp' (VISCA-over-IP header - Sony/AVer/Marshall) or 'tcp' (raw VISCA - PTZOptics) */
    private string $transport;
    /** Whether to wrap commands in the VISCA-over-IP header (2-byte type + 2-byte length + 4-byte sequence) */
    private bool $useIpHeader;
    /** Camera address, 1-7 */
    private int $address;
    private int $sequence = 0;

    const PAYLOAD_TYPE_COMMAND = 0x0100;
    const PAYLOAD_TYPE_INQUIRY = 0x0110;
    const PAYLOAD_TYPE_CONTROL_COMMAND = 0x0200;

    public function __construct(string $host, int $port = 52381, string $transport = 'udp', bool $useIpHeader = true, int $address = 1)
    {
        $this->host = $host;
        $this->port = $port;
        $this->transport = $transport;
        $this->useIpHeader = $useIpHeader;
        $this->address = $address;
    }

    /** First byte of every VISCA command: 0x80 + camera address. */
    private function addressByte(): int
    {
        return 0x80 + $this->address;
    }

    /**
     * Wrap a raw VISCA payload (bytes WITHOUT the address prefix / FF terminator)
     * in the address byte + FF terminator, e.g. [0x06,0x04] -> [0x81,0x06,0x04,0xFF]
     */
    public function envelope(array $payload): array
    {
        return array_merge([$this->addressByte()], $payload, [0xFF]);
    }

    /**
     * Build the full wire bytes for a command, including the VISCA-over-IP
     * header if enabled. Pure encoding - does not touch the network, safe to
     * unit test without a camera. See test-encode.php.
     */
    public function encode(array $viscaBytes): array
    {
        if (!$this->useIpHeader) {
            return $viscaBytes;
        }
        $len = count($viscaBytes);
        $seq = $this->sequence;
        $header = [
            (self::PAYLOAD_TYPE_COMMAND >> 8) & 0xFF, self::PAYLOAD_TYPE_COMMAND & 0xFF,
            ($len >> 8) & 0xFF, $len & 0xFF,
            ($seq >> 24) & 0xFF, ($seq >> 16) & 0xFF, ($seq >> 8) & 0xFF, $seq & 0xFF,
        ];
        return array_merge($header, $viscaBytes);
    }

    /**
     * Open the socket, send the encoded bytes, read the reply, close.
     * Requires real hardware - not exercised by test-encode.php.
     *
     * @return string raw reply bytes (ACK + Completion, or an error message)
     */
    public function send(array $viscaBytes): string
    {
        $wire = $this->encode($viscaBytes);
        $scheme = $this->transport === 'tcp' ? 'tcp' : 'udp';
        $socket = @stream_socket_client("{$scheme}://{$this->host}:{$this->port}", $errno, $errstr, 2);
        if (!$socket) {
            throw new RuntimeException("Could not connect to {$this->host}:{$this->port} - {$errstr}");
        }
        fwrite($socket, pack('C*', ...$wire));
        $this->sequence++;
        $reply = fread($socket, 64);
        fclose($socket);
        return $reply === false ? '' : $reply;
    }

    // ---- Semantic helpers (byte tables verified against the *-VISCA-API-REFERENCE.md docs) ----

    public function panTiltHome(): array
    {
        return $this->envelope([0x01, 0x06, 0x04]);
    }

    public function panTiltReset(): array
    {
        return $this->envelope([0x01, 0x06, 0x05]);
    }

    /**
     * @param int $panSpeed 1-24
     * @param int $tiltSpeed 1-24
     * @param string $direction one of: up, down, left, right, up-left, up-right, down-left, down-right, stop
     */
    public function panTilt(int $panSpeed, int $tiltSpeed, string $direction): array
    {
        $dirs = [
            'up' => [0x03, 0x01],
            'down' => [0x03, 0x02],
            'left' => [0x01, 0x03],
            'right' => [0x02, 0x03],
            'up-left' => [0x01, 0x01],
            'up-right' => [0x02, 0x01],
            'down-left' => [0x01, 0x02],
            'down-right' => [0x02, 0x02],
            'stop' => [0x03, 0x03],
        ];
        if (!isset($dirs[$direction])) {
            throw new InvalidArgumentException("Unknown direction: {$direction}");
        }
        return $this->envelope(array_merge([0x01, 0x06, 0x01, $panSpeed, $tiltSpeed], $dirs[$direction]));
    }

    public function panTiltStop(): array
    {
        return $this->panTilt(0x03, 0x03, 'stop');
    }

    public function zoomStop(): array
    {
        return $this->envelope([0x01, 0x04, 0x07, 0x00]);
    }

    /** @param int $speed 0-7, $direction 'in' or 'out' */
    public function zoom(int $speed, string $direction): array
    {
        $nibble = $direction === 'in' ? 0x20 : 0x30;
        return $this->envelope([0x01, 0x04, 0x07, $nibble | $speed]);
    }

    public function focusStop(): array
    {
        return $this->envelope([0x01, 0x04, 0x08, 0x00]);
    }

    public function focusAuto(bool $auto): array
    {
        return $this->envelope([0x01, 0x04, 0x38, $auto ? 0x02 : 0x03]);
    }

    public function power(bool $on): array
    {
        return $this->envelope([0x01, 0x04, 0x00, $on ? 0x02 : 0x03]);
    }

    /**
     * @param int $presetNumber 1-indexed, matching the AW-HE40 UI convention.
     *   Converted to the 0-indexed wire value internally (every VISCA brand's convention).
     */
    public function presetRecall(int $presetNumber): array
    {
        return $this->envelope([0x01, 0x04, 0x3F, 0x02, $presetNumber - 1]);
    }

    public function presetSave(int $presetNumber): array
    {
        return $this->envelope([0x01, 0x04, 0x3F, 0x01, $presetNumber - 1]);
    }
}
