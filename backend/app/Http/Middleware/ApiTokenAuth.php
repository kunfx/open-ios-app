<?php

namespace App\Http\Middleware;

use App\Models\ApiToken;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * 移动端 Bearer Token 鉴权中间件。
 *
 * 用法：
 *   ->middleware('api.token')      必须登录
 *   ->middleware('api.token:0')    可选登录（带 token 就识别用户，不带也放行）
 *
 * 安全要点：
 * - 数据库只保存 SHA-256 哈希，明文 token 只在登录时返回一次。
 * - 每次请求都会校验 token 是否过期、用户是否仍然存在。
 * - 校验通过后把用户注入 web guard，便于复用 DownloadController 等现有逻辑。
 */
class ApiTokenAuth
{
    public function handle(Request $request, Closure $next, string $required = '1'): Response
    {
        $isRequired = $required !== '0';
        $plainToken = $request->bearerToken();

        if (! $plainToken) {
            return $isRequired ? $this->unauthorized('请先登录', 'NEED_LOGIN') : $next($request);
        }

        $token = ApiToken::query()
            ->with('user')
            ->where('token_hash', ApiToken::hashToken($plainToken))
            ->first();

        if (! $token) {
            return $isRequired
                ? $this->unauthorized('登录凭证无效，请重新登录', 'TOKEN_INVALID')
                : $next($request);
        }

        if ($token->expires_at && $token->expires_at->isPast()) {
            $token->delete();

            return $isRequired
                ? $this->unauthorized('登录已过期，请重新登录', 'TOKEN_EXPIRED')
                : $next($request);
        }

        $user = $token->user;

        if (! $user) {
            $token->delete();

            return $isRequired
                ? $this->unauthorized('账号不存在，请重新登录', 'USER_NOT_FOUND')
                : $next($request);
        }

        // 记录最近使用时间，便于用户在后台/接口层审计
        $token->forceFill([
            'last_used_at' => now(),
            'last_used_ip' => $request->ip(),
        ])->save();

        // 让 auth()->user()、Auth::check() 以及现有控制器（DownloadController）都能拿到用户
        Auth::guard('web')->setUser($user);
        $request->setUserResolver(fn () => $user);
        $request->attributes->set('api_token', $token);

        return $next($request);
    }

    private function unauthorized(string $message, string $status): Response
    {
        return response()->json([
            'success' => false,
            'status' => $status,
            'message' => $message,
        ], 401);
    }
}
