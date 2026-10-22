<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Models\Setting;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

trait PresentsUser
{
    /**
     * 统一的用户资料结构：积分 / VIP / 今日免费额度 / 签到 / 未读消息。
     */
    protected function userPayload(User $user): array
    {
        $isAdmin = (bool) $user->is_admin;
        $vipActive = $user->isVipActive();
        $unlimited = $isAdmin || $vipActive;

        $freeLimit = max(0, (int) Setting::get('free_limit_vip0', 3));
        $freeUsed = $this->todayFreeUsed($user);

        $freeLeft = $unlimited
            ? -1
            : max(0, $freeLimit - $freeUsed);

        return [
            'id' => (int) $user->id,
            'name' => (string) $user->name,
            'email' => (string) $user->email,
            'avatar' => $this->absoluteUrl($user->avatar),
            'points' => (int) $user->points,
            'vip_level' => (int) $user->vip_level,
            'vip_level_text' => $user->vip_level_text,
            'vip_active' => $vipActive,
            'vip_expired_at' => $user->vip_expired_at?->toIso8601String(),
            'vip_expired_text' => $user->vip_expired_text,
            'is_admin' => $isAdmin,
            'created_at' => $user->created_at?->toIso8601String(),
            'free_limit_today' => $freeLimit,
            'free_used_today' => $freeUsed,
            'free_left_today' => $freeLeft,
            'unlimited_downloads' => $unlimited,
            'signed_today' => $this->signedToday((int) $user->id),
            'unread_messages' => $this->unreadMessages((int) $user->id),
            'must_change_password' => Hash::check('123456', (string) $user->password),
        ];
    }

    protected function todayFreeUsed(User $user): int
    {
        return (int) DB::table('download_logs')
            ->join('apps', 'download_logs.app_id', '=', 'apps.id')
            ->where('download_logs.user_id', $user->id)
            ->whereDate('download_logs.created_at', Carbon::today())
            ->where('download_logs.points_spent', 0)
            ->where(function ($query) {
                $query->whereNull('apps.points_required')
                    ->orWhere('apps.points_required', '<=', 0);
            })
            ->count();
    }

    protected function signedToday(int $userId): bool
    {
        if (! Schema::hasTable('user_sign_ins')) {
            return false;
        }

        return DB::table('user_sign_ins')
            ->where('user_id', $userId)
            ->whereDate('sign_date', Carbon::today())
            ->exists();
    }

    protected function unreadMessages(int $userId): int
    {
        $hasNotifications = Schema::hasTable('notifications');
        $hasUserNotifications = Schema::hasTable('user_notifications');

        // 站点两套消息表并存时，优先使用当前用户真正有数据的那一张。
        if ($hasUserNotifications
            && DB::table('user_notifications')->where('user_id', $userId)->exists()) {
            return (int) DB::table('user_notifications')
                ->where('user_id', $userId)
                ->where('is_read', 0)
                ->count();
        }

        if ($hasNotifications
            && DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $userId)
                ->exists()) {
            return (int) DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $userId)
                ->whereNull('read_at')
                ->count();
        }

        if ($hasUserNotifications) {
            return (int) DB::table('user_notifications')
                ->where('user_id', $userId)
                ->where('is_read', 0)
                ->count();
        }

        if ($hasNotifications) {
            return (int) DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $userId)
                ->whereNull('read_at')
                ->count();
        }

        return 0;
    }

    protected function categoryRef($category): ?array
    {
        if (! $category) {
            return null;
        }

        return [
            'id' => (int) $category->id,
            'name' => (string) $category->name,
            'slug' => (string) $category->slug,
        ];
    }

    protected function isoDate($value): ?string
    {
        if (! $value) {
            return null;
        }

        return Carbon::parse($value)->toIso8601String();
    }

    protected function plainText(?string $html, int $limit = 0): string
    {
        $text = strip_tags((string) $html);
        $text = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $text = trim(preg_replace('/\s+/u', ' ', $text) ?? '');

        if ($limit > 0 && Str::length($text) > $limit) {
            return Str::limit($text, $limit, '…');
        }

        return $text;
    }
}
