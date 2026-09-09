<?php
/**
 * VPNGate → sing-box 订阅转换层（单文件）
 *
 * 与 mihomo 版的区别不只是换个序列化格式。sing-box 里 OpenVPN 不是 outbound 而是
 * endpoint（1.14.0 起），字段名、证书的承载方式、压缩和 tls-auth 的表达全都不同，
 * 所以这是一次重写而不是一次改写。
 *
 * 用法:
 *   https://你的域名/vpngate2singbox.php?token=你的密钥
 *   可选参数:
 *     &country=US,JP      只保留指定国家/地区（ISO 代码，逗号分隔）
 *     &limit=100          最多输出节点数（默认 100，上限 300）
 *     &proto=tcp|udp|all  保留哪种传输层协议（默认 tcp，更抗封锁）
 *     &detour=中转tag     链式代理：所有节点都经由该出站落地（见下方「链式代理」）
 *     &full=1             输出完整配置（含 inbounds / route），默认只输出 endpoints
 *
 * 内核要求:
 *   sing-box >= 1.14.0。openvpn-client endpoint 是 1.14 引入的，更早的内核会直接
 *   拒绝这份配置。注意 SingBox Client 当前的 singBoxMinimumVersion 是 (1, 12)，
 *   要用这份订阅得先把内核升到 1.14+。
 *
 * 链式代理:
 *   endpoint 合并了 sing-box 的 Dial Fields，所以 detour 在它上面有效：
 *   detour 指向哪个出站，这条 endpoint 的流量就从那里出去，也就是
 *   「机房中转 → 家宽落地」。有一个坑：一旦设了 detour，本 endpoint 的其他
 *   dial 字段（bind_interface、domain_resolver、connect_timeout 等）全部失效，
 *   因为 socket 是上游打开的——那些要写在上游那条出站上。
 *
 * 关于 VPNGate 本身:
 *   这是公开的志愿者节点池，不是独享线路。里面确实有家宽 IP，但都是公开共享的，
 *   早被各平台标记过，用于「解锁」类用途的效果不要抱期望。
 *
 * 兼容 PHP 7.4 / 8.x
 */

error_reporting(E_ALL & ~E_NOTICE);
ini_set('display_errors', 0);
@set_time_limit(60);
@ini_set('memory_limit', '256M');

const VPNGATE_URL = 'https://www.vpngate.net/api/iphone/';
const CACHE_TTL   = 3600;   // 缓存 1 小时，降低出网流量
const MAX_LIMIT   = 300;

/**
 * sing-box 接受的数据通道加密套件。
 *
 * 白名单而不是照抄：一个内核不认识的套件名会让整份配置在启动时被拒，而不是
 * 让那一个节点失效——一条坏线路不该拖垮整份订阅。
 */
const ALLOWED_CIPHERS = [
    'AES-128-GCM', 'AES-256-GCM', 'CHACHA20-POLY1305',
    'AES-128-CBC', 'AES-256-CBC',
];

/** 同理，数据通道摘要。sing-box 的默认值是 SHA1。 */
const ALLOWED_AUTH = ['MD5', 'SHA1', 'SHA256', 'SHA384', 'SHA512'];

/* ============ PHP 7.4 兼容 ============ */
if (!function_exists('str_starts_with')) {
    function str_starts_with($h, $n) { return $n !== '' && strncmp($h, $n, strlen($n)) === 0; }
}
if (!function_exists('str_contains')) {
    function str_contains($h, $n) { return $n === '' || strpos($h, $n) !== false; }
}

/* ============ 鉴权 ============ */
$token = isset($_GET['token']) ? (string)$_GET['token'] : '';
$expectedToken = getenv('VPNGATE2SINGBOX_TOKEN');
if (!is_string($expectedToken) || $expectedToken === '') {
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Service is not configured');
}
if ($token === '' || !hash_equals($expectedToken, $token)) {
    http_response_code(401);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Unauthorized');
}

/* ============ 请求参数 ============ */
$protoWanted = 'tcp';
if (isset($_GET['proto']) && in_array($_GET['proto'], ['tcp', 'udp', 'all'], true)) {
    $protoWanted = $_GET['proto'];
}
$countryWanted = [];
if (!empty($_GET['country'])) {
    foreach (explode(',', strtoupper((string)$_GET['country'])) as $c) {
        $c = trim($c);
        if (preg_match('/^[A-Z]{2}$/', $c)) $countryWanted[] = $c;
    }
}
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 100;
$limit = max(1, min($limit, MAX_LIMIT));
$full  = !empty($_GET['full']);

/**
 * 链式代理的上游出站 tag。
 *
 * 只做字符集校验、不校验存在性：这个 tag 指向的是使用方自己配置里的某条出站，
 * 这边无从得知它是否存在。tag 不存在时 sing-box 会在启动时报错，那个报错比这边
 * 猜一个更有用。
 */
$detour = '';
if (!empty($_GET['detour'])) {
    $candidate = trim((string)$_GET['detour']);
    if (preg_match('/^[A-Za-z0-9._\x{4e00}-\x{9fa5}-]{1,64}$/u', $candidate)) {
        $detour = $candidate;
    }
}

/* ============ 缓存目录（禁止 Web 直读） ============ */
$cacheDir = __DIR__ . '/cache';
if (!is_dir($cacheDir)) { @mkdir($cacheDir, 0755, true); }
if (is_dir($cacheDir)) {
    $ht = $cacheDir . '/.htaccess';
    if (!file_exists($ht)) { @file_put_contents($ht, "Require all denied\n"); }
    if (!file_exists($cacheDir . '/index.html')) { @file_put_contents($cacheDir . '/index.html', ''); }
}
$cacheKey  = md5($protoWanted . '|' . implode(',', $countryWanted) . '|' . $limit
    . '|' . ($full ? 1 : 0) . '|' . $detour);
$cacheFile = is_dir($cacheDir) ? $cacheDir . '/vg_' . substr($cacheKey, 0, 16) . '.json' : null;

/* ============ 主流程 ============ */
try {
    // 1. 命中缓存直接返回
    if ($cacheFile && file_exists($cacheFile) && (time() - filemtime($cacheFile) < CACHE_TTL)) {
        sendJson(file_get_contents($cacheFile), 'HIT');
    }

    // 2. 抓取 VPNGate CSV 并转换
    $nodes = fetchAndParseVPNGate(VPNGATE_URL, $protoWanted, $countryWanted, $limit);
    if (empty($nodes)) {
        // 源站抓取失败时回退旧缓存（尽力而为）
        if ($cacheFile && file_exists($cacheFile)) {
            sendJson(file_get_contents($cacheFile), 'STALE');
        }
        http_response_code(404);
        header('Content-Type: text/plain; charset=utf-8');
        exit('未解析到有效的 VPNGate 节点');
    }

    $json = $full
        ? dumpFullConfig($nodes, $detour)
        : dumpEndpoints($nodes, $detour);

    if ($cacheFile) { @file_put_contents($cacheFile, $json, LOCK_EX); }
    sendJson($json, 'MISS');

} catch (Exception $e) {
    if ($cacheFile && file_exists($cacheFile)) {
        sendJson(file_get_contents($cacheFile), 'STALE');
    }
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    exit('处理失败: ' . $e->getMessage());
}

exit;

/* ============ 输出 ============ */
function sendJson(string $json, string $cacheStatus): void {
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: inline; filename="vpngate.json"');
    header('Access-Control-Allow-Origin: *');
    header('X-Cache-Status: ' . $cacheStatus);
    echo $json;
    exit;
}

/* ============ HTTP 抓取（curl 优先，allow_url_fopen 兜底） ============ */
function httpGet(string $url): string {
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS      => 3,
            CURLOPT_TIMEOUT        => 25,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_USERAGENT      => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36',
        ]);
        $body = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        // PHP 8.0 起句柄由 GC 回收，8.5 起显式调用会产生 Deprecated 告警；
        // 但 7.4 仍需手动关闭，所以按版本分流而不是直接删掉。
        if (PHP_VERSION_ID < 80000) curl_close($ch);
        if ($body !== false && $code >= 200 && $code < 300) return $body;
        throw new Exception("抓取失败(HTTP {$code})");
    }
    $ctx = stream_context_create(['http' => [
        'method'  => 'GET',
        'header'  => "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/122.0\r\n",
        'timeout' => 25,
    ]]);
    $body = @file_get_contents($url, false, $ctx);
    if ($body === false) throw new Exception('抓取失败(allow_url_fopen 不可用或网络异常)');
    return $body;
}

/* ============ 抓取 + 解析 CSV ============ */
function fetchAndParseVPNGate(string $url, string $protoWanted, array $countryWanted, int $limit): array {
    $text = httpGet($url);
    $lines = preg_split('/\r?\n/', $text);
    $nodes = [];
    $seen  = []; // server|port 去重，保留速度快的

    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || $line[0] === '*') continue;

        $record = explode(',', $line);
        if (count($record) < 15) continue;

        $host    = trim($record[0]);
        $ip      = trim($record[1]);
        $score   = (int)$record[2];
        $ping    = (int)$record[3];
        $speed   = (int)$record[4];
        $cc      = strtoupper(trim($record[6]));
        $ovpnB64 = trim(end($record));

        if ($ovpnB64 === '') continue;
        $ovpn = base64_decode($ovpnB64, true);
        if ($ovpn === false) continue;

        if ($countryWanted && !in_array($cc, $countryWanted, true)) continue;

        $node = convertOvpnToSingBox($host !== '' ? $host : $ip, $ovpn);
        if ($node === null) continue;

        if ($protoWanted !== 'all' && $node['network'] !== $protoWanted) continue;

        $node['name']   = ($cc !== '' ? $cc : 'VG') . '-' . $node['name'];
        $node['_score'] = $score;
        $node['_speed'] = $speed;
        $node['_ping']  = $ping;

        $dupKey = strtolower($node['server']) . '|' . $node['server_port'];
        if (isset($seen[$dupKey])) {
            if ($speed > $seen[$dupKey]['_speed']) {
                foreach ($nodes as $i => $n) {
                    if ($n['server'] === $seen[$dupKey]['server']
                        && $n['server_port'] === $seen[$dupKey]['server_port']) {
                        $nodes[$i] = $node;
                        break;
                    }
                }
                $seen[$dupKey] = $node;
            }
            continue;
        }
        $seen[$dupKey] = $node;
        $nodes[] = $node;
    }

    // 速度优先排序，截取 limit 个
    usort($nodes, function ($a, $b) {
        if ($b['_speed'] !== $a['_speed']) return $b['_speed'] <=> $a['_speed'];
        return $b['_score'] <=> $a['_score'];
    });
    $nodes = array_slice($nodes, 0, $limit);

    // 名称去重。这里比 mihomo 版更要紧：tag 在 sing-box 里是引用键，重复的 tag
    // 会让 urltest 组引用到错的那条，而不是报错。
    $usedNames = [];
    foreach ($nodes as $i => $n) {
        $name = $n['name'];
        if (isset($usedNames[$name])) {
            $usedNames[$name]++;
            $name = $name . '-' . $usedNames[$name];
        } else {
            $usedNames[$name] = 1;
        }
        $nodes[$i]['name'] = $name;
    }

    return $nodes;
}

/* ============ .ovpn → sing-box openvpn-client endpoint ============ */
/**
 * 解析一份 .ovpn，产出中间结构（尚未渲染成 endpoint）。
 *
 * 中间结构而不是直接产出最终 JSON：排序、去重、加国家前缀都发生在这之后，
 * 而那些步骤不该关心 tls 子对象长什么样。
 */
function convertOvpnToSingBox(string $name, string $ovpn): ?array {
    $node = [
        'name'        => preg_replace('/[^A-Za-z0-9._-]/', '', $name),
        'network'     => 'udp',
        'server'      => '',
        'server_port' => 1194,
    ];

    foreach (explode("\n", $ovpn) as $line) {
        $line = trim($line);

        if ($node['server'] === '' && preg_match('/^remote\s+(\S+)\s+(\d+)/i', $line, $m)) {
            $node['server']      = $m[1];
            $node['server_port'] = (int)$m[2];
        }
        // OpenVPN 的 proto 是传输层，对应 sing-box 的 network——不是 mihomo 那个
        // 表示「隧道内是否放行 UDP」的 udp 字段。两者同名不同义，容易混。
        if (preg_match('/^proto\s+(tcp|udp)/i', $line, $m)) {
            $node['network'] = strtolower($m[1]);
        }
        // TLS 模式下 sing-box 忽略 cipher，所以这条 ovpn 指令要落到
        // data_ciphers_fallback 上，否则老服务器协商不出套件就直接断。
        if (!isset($node['cipher_fallback']) && preg_match('/^cipher\s+(\S+)/i', $line, $m)) {
            $c = strtoupper($m[1]);
            if (in_array($c, ALLOWED_CIPHERS, true)) $node['cipher_fallback'] = $c;
        }
        if (!isset($node['auth']) && preg_match('/^auth\s+(\S+)/i', $line, $m)) {
            $a = strtoupper($m[1]);
            if (in_array($a, ALLOWED_AUTH, true)) $node['auth'] = $a;
        }
        if (!isset($node['data_ciphers']) && preg_match('/^data-ciphers\s+(\S+)/i', $line, $m)) {
            $list = [];
            foreach (explode(':', strtoupper($m[1])) as $c) {
                if (in_array($c, ALLOWED_CIPHERS, true) && !in_array($c, $list, true)) {
                    $list[] = $c;
                }
            }
            if ($list) $node['data_ciphers'] = $list;
        }
        // comp-lzo / compress 分别对应两个不同字段，不能合并：sing-box 用
        // compression_lzo 表示前者的帧格式，compression 表示后者。
        if (!isset($node['compression_lzo']) && preg_match('/^comp-lzo(?:\s+(\S+))?\s*$/i', $line, $m)) {
            $node['compression_lzo'] = isset($m[1]) && $m[1] !== ''
                ? strtolower($m[1])
                : 'adaptive'; // 裸 comp-lzo 就是 adaptive
        }
        if (!isset($node['compression']) && preg_match('/^compress(?:\s+(\S+))?\s*$/i', $line, $m)) {
            // 裸 compress 是 stub。压缩会削弱流量的保密性，所以只在 ovpn 明确要求
            // 时才带上，且优先用只对齐帧格式的 stub 系。
            $node['compression'] = isset($m[1]) && $m[1] !== ''
                ? strtolower($m[1])
                : 'stub';
        }
        if (!isset($node['key_direction']) && preg_match('/^key-direction\s+(\S+)/i', $line, $m)) {
            $node['key_direction'] = strtolower($m[1]);
        }
        if (!isset($node['remote_cert_tls']) && preg_match('/^remote-cert-tls\s+(\S+)/i', $line, $m)) {
            $node['remote_cert_tls'] = strtolower($m[1]);
        }
        if (!isset($node['mtu']) && preg_match('/^tun-mtu\s+(\d+)/i', $line, $m)) {
            $node['mtu'] = (int)$m[1];
        }
    }

    $node['ca']   = extractXMLBlock($ovpn, 'ca');
    $node['cert'] = extractXMLBlock($ovpn, 'cert');
    $node['key']  = extractXMLBlock($ovpn, 'key');

    // 控制通道包装。三种 ovpn 指令在 sing-box 里合并成一个 control_wrap 对象，
    // 只是 type 不同。
    foreach (['tls-crypt-v2' => 'tls_crypt_v2', 'tls-crypt' => 'tls_crypt', 'tls-auth' => 'tls_auth'] as $tag => $type) {
        $value = extractXMLBlock($ovpn, $tag);
        if ($value !== '') {
            $node['control_wrap'] = ['type' => $type, 'key' => $value];
            break; // 一份配置只会用其中一种
        }
    }

    // 内联的用户名密码。VPNGate 是证书模式，一般没有这一段，但带上不亏。
    $userPass = extractXMLBlock($ovpn, 'auth-user-pass');
    if ($userPass !== '') {
        $parts = preg_split('/\r?\n/', trim($userPass));
        if (count($parts) >= 2) {
            $node['username'] = trim($parts[0]);
            $node['password'] = trim($parts[1]);
        }
    }

    if ($node['server'] === '' || $node['ca'] === '') return null;
    // sing-box 要求客户端证书和私钥「同时提供或同时留空」，半套会在启动时被拒。
    if ($node['cert'] === '' || $node['key'] === '') return null;
    return $node;
}

function extractXMLBlock(string $content, string $tag): string {
    $pattern = '/<' . preg_quote($tag, '/') . '>([\s\S]*?)<\/' . preg_quote($tag, '/') . '>/i';
    if (preg_match($pattern, $content, $m) && trim($m[1]) !== '') {
        return trim($m[1]);
    }
    return '';
}

/* ============ 渲染 ============ */
/**
 * PEM 文本 → sing-box 接受的行数组。
 *
 * 内联而不是写文件：这是一个订阅接口，落地端没有可以放证书的路径。sing-box 的
 * certificate / client_key 等字段都接受行数组，单行时也可以直接写字符串——统一
 * 用数组，省掉一个分支。
 *
 * 真机部署时更稳妥的做法是用 *_path 字段把私钥留在配置之外，但订阅这个形态做不到。
 */
function pemLines(string $pem): array {
    $lines = [];
    foreach (preg_split('/\r?\n/', trim($pem)) as $line) {
        $line = rtrim($line);
        if ($line !== '') $lines[] = $line;
    }
    return $lines;
}

/** 一条 openvpn-client endpoint。 */
function buildEndpoint(array $n, string $detour): array {
    $tls = [
        // VPNGate 的证书普遍是 SHA1 签名、密钥偏短的老货。不加 legacy 的话
        // sing-box 会按现代 profile 校验并整条拒掉——这是最容易踩的一处。
        'certificate_profile' => 'legacy',
        'certificate'         => pemLines($n['ca']),
        'client_certificate'  => pemLines($n['cert']),
        'client_key'          => pemLines($n['key']),
    ];
    if (!empty($n['remote_cert_tls'])) {
        $tls['remote_certificate_tls'] = $n['remote_cert_tls'];
    }
    if (!empty($n['control_wrap'])) {
        $wrap = [
            'type' => $n['control_wrap']['type'],
            'key'  => pemLines($n['control_wrap']['key']),
        ];
        // direction 只对 tls_auth 有意义，留空即双向。
        if ($n['control_wrap']['type'] === 'tls_auth' && isset($n['key_direction'])) {
            $wrap['direction'] = $n['key_direction'];
        }
        $tls['control_wrap'] = $wrap;
    }

    $endpoint = [
        'type'        => 'openvpn-client',
        'tag'         => $n['name'],
        'mode'        => 'tls',
        'server'      => $n['server'],
        'server_port' => $n['server_port'],
        'network'     => $n['network'],
        'tls'         => $tls,
    ];

    if (!empty($n['username'])) {
        $endpoint['username'] = $n['username'];
        $endpoint['password'] = isset($n['password']) ? $n['password'] : '';
    }
    if (!empty($n['data_ciphers']))    $endpoint['data_ciphers'] = $n['data_ciphers'];
    if (!empty($n['cipher_fallback'])) $endpoint['data_ciphers_fallback'] = $n['cipher_fallback'];
    if (!empty($n['auth']))            $endpoint['auth'] = $n['auth'];
    if (!empty($n['compression']))     $endpoint['compression'] = $n['compression'];
    if (!empty($n['compression_lzo'])) $endpoint['compression_lzo'] = $n['compression_lzo'];
    if (!empty($n['mtu']))             $endpoint['mtu'] = $n['mtu'];

    // 链式代理。放在最后是有意的：detour 一旦存在，本 endpoint 的其他 dial 字段
    // 就都失效了，所以这里也不该再往下写 dial 相关的东西。
    if ($detour !== '') $endpoint['detour'] = $detour;

    return $endpoint;
}

function encode(array $data): string {
    return json_encode(
        $data,
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    ) . "\n";
}

/** 只输出 endpoints，供使用方并进自己的配置。 */
function dumpEndpoints(array $nodes, string $detour): string {
    $endpoints = [];
    foreach ($nodes as $n) $endpoints[] = buildEndpoint($n, $detour);
    return encode(['endpoints' => $endpoints]);
}

/* ============ 完整配置模式（?full=1） ============ */
function dumpFullConfig(array $nodes, string $detour): string {
    $endpoints = [];
    $tags      = [];
    foreach ($nodes as $n) {
        $endpoints[] = buildEndpoint($n, $detour);
        $tags[]      = $n['name'];
    }

    return encode([
        'log' => ['level' => 'info', 'timestamp' => true],
        'inbounds' => [[
            'type'        => 'mixed',
            'tag'         => 'mixed-in',
            // 只监听回环。sing-box 的默认监听地址是 ::，那会把一个开放代理
            // 暴露给整个局域网。
            'listen'      => '127.0.0.1',
            'listen_port' => 7890,
        ]],
        // endpoint tag 可以直接被 selector / urltest 引用，所以节点本身不必再包一层。
        'endpoints' => $endpoints,
        'outbounds' => [
            [
                'type'      => 'selector',
                'tag'       => 'PROXY',
                'outbounds' => array_merge(['AUTO', 'direct'], $tags),
                'default'   => 'AUTO',
            ],
            [
                'type'      => 'urltest',
                'tag'       => 'AUTO',
                'outbounds' => $tags,
                'url'       => 'http://www.gstatic.com/generate_204',
                'interval'  => '10m',
                'tolerance' => 80,
            ],
            ['type' => 'direct', 'tag' => 'direct'],
        ],
        'route' => [
            'rules' => [
                // 面板和内核自己的流量不能再进代理，否则测速会绕圈。
                ['action' => 'sniff'],
                ['protocol' => 'dns', 'action' => 'hijack-dns'],
                ['ip_is_private' => true, 'outbound' => 'direct'],
            ],
            'final'     => 'PROXY',
            'auto_detect_interface' => true,
        ],
    ]);
}
