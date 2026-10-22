<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class MessageController extends Controller
{
    use RespondsWithJson;

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $perPage = min(50, max(1, $request->integer('per_page', 20)));
        $page = max(1, $request->integer('page', 1));

        $source = $this->sourceFor((int) $user->id);

        if ($source === 'notifications') {
            $paginator = DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $user->id)
                ->orderByDesc('created_at')
                ->paginate($perPage, ['*'], 'page', $page);

            $items = collect($paginator->items())->map(function ($row) {
                $data = json_decode((string) ($row->data ?? '{}'), true) ?: [];

                $actionUrl = null;

                if (! empty($data['actions']) && is_array($data['actions'])) {
                    $actionUrl = $data['actions'][0]['url'] ?? null;
                }

                $body = $data['body'] ?? ($data['message'] ?? null);

                if (is_array($body)) {
                    $body = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
                } elseif ($body !== null) {
                    $body = (string) $body;
                }

                $url = $data['url'] ?? $actionUrl;
                $title = $data['title'] ?? '系统通知';
                $color = $data['color'] ?? null;

                return [
                    'id' => (string) $row->id,
                    'title' => is_scalar($title) ? (string) $title : '系统通知',
                    'body' => $body,
                    'url' => is_string($url) ? $url : null,
                    'color' => is_scalar($color) ? (string) $color : null,
                    'is_read' => ! empty($row->read_at),
                    'created_at' => $this->isoDate($row->created_at),
                ];
            })->values()->all();

            return $this->ok(array_merge(
                $this->paginated($paginator, $items),
                ['unread_count' => $this->unreadCount((int) $user->id, $source)]
            ));
        }

        if ($source === 'user_notifications') {
            $paginator = DB::table('user_notifications')
                ->where('user_id', $user->id)
                ->orderByDesc('id')
                ->paginate($perPage, ['*'], 'page', $page);

            $items = collect($paginator->items())->map(fn ($row) => [
                'id' => (string) $row->id,
                'title' => (string) ($row->title ?? '系统通知'),
                'body' => $row->content,
                'url' => $row->url,
                'color' => null,
                'is_read' => (bool) ($row->is_read ?? false),
                'created_at' => $this->isoDate($row->created_at),
            ])->values()->all();

            return $this->ok(array_merge(
                $this->paginated($paginator, $items),
                ['unread_count' => $this->unreadCount((int) $user->id, $source)]
            ));
        }

        return $this->ok([
            'items' => [],
            'page' => 1,
            'per_page' => $perPage,
            'total' => 0,
            'last_page' => 1,
            'has_more' => false,
            'unread_count' => 0,
        ]);
    }

    public function markRead(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $source = $this->sourceFor((int) $user->id);

        if ($source === 'notifications') {
            DB::table('notifications')
                ->where('id', $id)
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $user->id)
                ->update(['read_at' => now(), 'updated_at' => now()]);
        } elseif ($source === 'user_notifications') {
            DB::table('user_notifications')
                ->where('id', $id)
                ->where('user_id', $user->id)
                ->update(['is_read' => 1, 'read_at' => now(), 'updated_at' => now()]);
        }

        return $this->ok(
            ['unread_count' => $this->unreadCount((int) $user->id, $source)],
            '已标记为已读'
        );
    }

    public function markAllRead(Request $request): JsonResponse
    {
        $user = $request->user();
        $source = $this->sourceFor((int) $user->id);

        if ($source === 'notifications') {
            DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $user->id)
                ->whereNull('read_at')
                ->update(['read_at' => now(), 'updated_at' => now()]);
        } elseif ($source === 'user_notifications') {
            DB::table('user_notifications')
                ->where('user_id', $user->id)
                ->where('is_read', 0)
                ->update(['is_read' => 1, 'read_at' => now(), 'updated_at' => now()]);
        }

        return $this->ok(['unread_count' => 0], '全部消息已读');
    }

    /**
     * 站点同时存在两种消息表：
     * - notifications         Laravel 标准通知表（可能只是默认迁移留下的空表）
     * - user_notifications    站内自定义消息表
     *
     * 优先使用“当前用户确实有数据”的那张表，避免空的标准表把真实消息挡住。
     */
    private function sourceFor(int $userId): ?string
    {
        $hasNotifications = Schema::hasTable('notifications');
        $hasUserNotifications = Schema::hasTable('user_notifications');

        if ($hasUserNotifications
            && DB::table('user_notifications')->where('user_id', $userId)->exists()) {
            return 'user_notifications';
        }

        if ($hasNotifications
            && DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $userId)
                ->exists()) {
            return 'notifications';
        }

        if ($hasUserNotifications) {
            return 'user_notifications';
        }

        return $hasNotifications ? 'notifications' : null;
    }

    private function unreadCount(int $userId, ?string $source = null): int
    {
        $source ??= $this->sourceFor($userId);

        if ($source === 'notifications') {
            return (int) DB::table('notifications')
                ->where('notifiable_type', User::class)
                ->where('notifiable_id', $userId)
                ->whereNull('read_at')
                ->count();
        }

        if ($source === 'user_notifications') {
            return (int) DB::table('user_notifications')
                ->where('user_id', $userId)
                ->where('is_read', 0)
                ->count();
        }

        return 0;
    }

    private function isoDate($value): ?string
    {
        if (! $value) {
            return null;
        }

        return Carbon::parse($value)->toIso8601String();
    }
}
