<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\App as ResourceApp;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\URL;

/**
 * 2 小时有效的下载跳转入口。
 *
 * 安全模型与网站现有 temporaryDownload 保持一致：
 * - 链接必须带 Laravel 签名（由下载接口在用户通过积分/额度校验后才生成）。
 * - 签名只证明“该用户完成过校验”，真实地址永远不会出现在 App 的接口响应里。
 */
class DownloadLinkController extends Controller
{
    public function redirect(Request $request, ResourceApp $app, int $index)
    {
        if (! $request->hasValidRelativeSignature()) {
            abort(403, '下载链接无效或已过期，请返回应用详情页重新获取');
        }

        $expires = (int) $request->query('expires', 0);

        if ($expires <= time()) {
            abort(403, '下载链接已过期，请返回应用详情页重新获取');
        }

        $links = $app->download_links;

        if (is_string($links)) {
            $links = json_decode($links, true);
        }

        $links = is_array($links) ? array_values($links) : [];

        if (! isset($links[$index]) || empty($links[$index]['url'])) {
            abort(404, '下载地址不存在');
        }

        $url = trim((string) $links[$index]['url']);

        if (! filter_var($url, FILTER_VALIDATE_URL)) {
            abort(404, '下载地址无效');
        }

        if (! in_array(strtolower((string) parse_url($url, PHP_URL_SCHEME)), ['http', 'https'], true)) {
            abort(403, '下载协议不受支持');
        }

        return redirect()->away($this->signPanDownloadUrl($url, $expires));
    }

    /**
     * 仅为 pan.ifeng.app 域名下的 IPA 生成 Nginx secure_link。
     * 密钥优先读 .env 的 PAN_SECURE_LINK_SECRET，未配置时与网站现有实现保持一致。
     */
    private function signPanDownloadUrl(string $url, int $expires): string
    {
        $parts = parse_url($url);

        if ($parts === false) {
            return $url;
        }

        $host = strtolower((string) ($parts['host'] ?? ''));
        $path = (string) ($parts['path'] ?? '');

        if ($host !== 'pan.ifeng.app' || ! preg_match('/\.ipa$/i', $path)) {
            return $url;
        }

        $secret = (string) env(
            'PAN_SECURE_LINK_SECRET',
            'IFeng_Pan_2026_N7qL4xV9mK2pR8cT5sH1'
        );

        $signUri = rawurldecode($path);
        $binaryHash = md5($expires . $signUri . ' ' . $secret, true);
        $token = rtrim(strtr(base64_encode($binaryHash), '+/', '-_'), '=');

        $separator = str_contains($url, '?') ? '&' : '?';

        return $url . $separator
            . 'st=' . rawurlencode($token)
            . '&e=' . $expires;
    }
}
