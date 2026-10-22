<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Models\ApiToken;
use App\Models\User;
use Illuminate\Support\Str;

trait IssuesApiTokens
{
    /**
     * 生成一次性返回给 App 的明文 token，数据库只留哈希。
     *
     * @return array{0:string,1:\Carbon\CarbonInterface}
     */
    protected function issueToken(User $user, ?string $deviceName = null): array
    {
        $plainToken = bin2hex(random_bytes(32));
        $ttlDays = max(1, (int) env('API_TOKEN_TTL_DAYS', 90));
        $expiresAt = now()->addDays($ttlDays);

        ApiToken::query()->create([
            'user_id' => $user->id,
            'name' => Str::limit($deviceName ?: 'ios-app', 60, ''),
            'token_hash' => ApiToken::hashToken($plainToken),
            'expires_at' => $expiresAt,
        ]);

        $this->pruneTokens($user);

        return [$plainToken, $expiresAt];
    }

    /**
     * 每个账号最多保留 10 个有效设备 token，避免 token 表无限增长。
     */
    protected function pruneTokens(User $user): void
    {
        ApiToken::query()
            ->where('user_id', $user->id)
            ->where('expires_at', '<', now())
            ->delete();

        $keepIds = ApiToken::query()
            ->where('user_id', $user->id)
            ->orderByDesc('id')
            ->limit(10)
            ->pluck('id');

        if ($keepIds->isNotEmpty()) {
            ApiToken::query()
                ->where('user_id', $user->id)
                ->whereNotIn('id', $keepIds)
                ->delete();
        }
    }

    protected function authPayload(User $user, string $plainToken, $expiresAt): array
    {
        return [
            'token' => $plainToken,
            'token_type' => 'Bearer',
            'token_expires_at' => $expiresAt?->toIso8601String(),
            'user' => $this->userPayload($user),
        ];
    }
}
