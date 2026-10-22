<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\IssuesApiTokens;
use App\Http\Controllers\Api\Concerns\PresentsUser;
use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Models\PointLog;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    use IssuesApiTokens, PresentsUser, RespondsWithJson;

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'password' => ['required', 'string', 'max:255'],
            'device_name' => ['nullable', 'string', 'max:60'],
        ]);

        $email = mb_strtolower(trim($data['email']));
        $rateKey = 'api-login:' . $email . '|' . $request->ip();

        if (RateLimiter::tooManyAttempts($rateKey, 5)) {
            $seconds = RateLimiter::availableIn($rateKey);

            return $this->fail("尝试次数过多，请 {$seconds} 秒后再试", 429);
        }

        $user = User::query()->where('email', $email)->first();

        // 统一提示，避免暴露“邮箱是否已注册”
        if (! $user || ! Hash::check($data['password'], $user->password)) {
            RateLimiter::hit($rateKey, 60);

            return $this->fail('邮箱或密码错误，请重新输入', 422);
        }

        RateLimiter::clear($rateKey);

        $user->forceFill([
            'last_login_at' => now(),
            'last_login_ip' => $request->ip(),
        ])->save();

        [$plainToken, $expiresAt] = $this->issueToken($user, $data['device_name'] ?? null);

        return $this->ok(
            $this->authPayload($user->fresh(), $plainToken, $expiresAt),
            '登录成功'
        );
    }

    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:6', 'max:72', 'confirmed'],
            'name' => ['nullable', 'string', 'max:50'],
            'device_name' => ['nullable', 'string', 'max:60'],
        ]);

        $email = mb_strtolower(trim($data['email']));
        $domain = mb_strtolower((string) Str::after($email, '@'));

        // 与网站注册保持一致：限制常见邮箱，减少垃圾注册
        $allowedDomains = ['qq.com', '163.com', 'gmail.com', 'sina.com'];

        if (! in_array($domain, $allowedDomains, true)) {
            return $this->fail('仅支持 QQ、163、Gmail、新浪邮箱注册', 422, [
                'email' => ['仅支持 QQ、163、Gmail、新浪邮箱注册'],
            ]);
        }

        $ip = (string) $request->ip();

        if (filter_var(env('API_REGISTER_UNIQUE_IP', true), FILTER_VALIDATE_BOOL)
            && User::query()->where('register_ip', $ip)->exists()) {
            return $this->fail('该网络已注册过账号，请直接登录或更换网络', 422, [
                'email' => ['该网络已注册过账号'],
            ]);
        }

        $name = trim((string) ($data['name'] ?? ''));

        if ($name === '') {
            $name = Str::before($email, '@');
        }

        $name = mb_substr($name, 0, 20);

        if ($name === '' || mb_strlen($name) < 2) {
            $name = '用户' . random_int(1000, 9999);
        }

        $defaultPoints = max(0, (int) \App\Models\Setting::get('register_points', 10));

        $user = DB::transaction(function () use ($name, $email, $data, $ip, $defaultPoints) {
            $user = User::query()->create([
                'name' => $name,
                'email' => $email,
                'password' => $data['password'],
                'vip_level' => 0,
                'points' => $defaultPoints,
                'register_ip' => $ip,
                'last_login_ip' => $ip,
                'last_login_at' => now(),
            ]);

            if ($defaultPoints > 0) {
                PointLog::query()->create([
                    'user_id' => $user->id,
                    'type' => 'register',
                    'action' => 1,
                    'points' => $defaultPoints,
                    'before_points' => 0,
                    'after_points' => $defaultPoints,
                    'target_id' => $user->id,
                    'target_type' => 'user_register',
                    'description' => '注册赠送：+' . $defaultPoints,
                ]);
            }

            return $user;
        });

        [$plainToken, $expiresAt] = $this->issueToken($user, $data['device_name'] ?? null);

        return $this->ok(
            $this->authPayload($user->fresh(), $plainToken, $expiresAt),
            '注册成功'
        );
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->attributes->get('api_token');

        if ($token) {
            $token->delete();
        }

        return $this->ok(null, '已退出登录');
    }

    /**
     * 当前 token 对应的用户资料（等价于 /api/user/profile 的轻量版本）。
     */
    public function me(Request $request): JsonResponse
    {
        return $this->ok($this->userPayload($request->user()));
    }
}
