<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\PresentsUser;
use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Models\PointLog;
use App\Models\Setting;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

class UserController extends Controller
{
    use PresentsUser, RespondsWithJson;

    public function profile(Request $request): JsonResponse
    {
        return $this->ok($this->userPayload($request->user()));
    }

    public function updateProfile(Request $request): JsonResponse
    {
        $name = trim((string) $request->input('name', ''));

        $validator = \Illuminate\Support\Facades\Validator::make(
            [
                'name' => $name,
                'avatar' => $request->input('avatar'),
                'password' => $request->input('password'),
                'password_confirmation' => $request->input('password_confirmation'),
            ],
            [
                'name' => ['required', 'string', 'max:255'],
                'avatar' => ['nullable', 'string', 'max:2048'],
                'password' => ['nullable', 'string', 'min:6', 'max:72', 'confirmed'],
            ],
            [
                'name.required' => '昵称不能为空',
                'name.max' => '昵称长度不能超过 255 个字符',
                'password.min' => '新密码至少需要 6 个字符',
                'password.confirmed' => '两次输入的新密码不一致',
            ]
        );

        if ($validator->fails()) {
            return $this->fail($validator->errors()->first(), 422, $validator->errors()->toArray());
        }

        $forbiddenWords = [
            '管理员', '超级管理员', '站长', 'admin', 'administrator', '爱锋',
            '官方', '客服', '私信', '广告', '点我', '加我', '联系人', '扫码',
            '微信', '公众号', 'QQ群', '加群', '代理', '推广',
        ];

        $normalizedName = mb_strtolower($name, 'UTF-8');

        foreach ($forbiddenWords as $word) {
            if (mb_strpos($normalizedName, mb_strtolower($word, 'UTF-8'), 0, 'UTF-8') !== false) {
                return $this->fail('该昵称禁止使用，请更换昵称后重试', 422, [
                    'name' => ['该昵称禁止使用'],
                ]);
            }
        }

        $user = $request->user();
        $user->name = $name;

        if ($request->filled('avatar')) {
            $user->avatar = (string) $request->input('avatar');
        }

        $passwordChanged = false;

        if ($request->filled('password')) {
            $user->password = Hash::make((string) $request->input('password'));
            $passwordChanged = true;
        }

        $user->save();

        return $this->ok(
            $this->userPayload($user->fresh()),
            $passwordChanged ? '密码修改成功' : '资料保存成功'
        );
    }

    public function signIn(Request $request): JsonResponse
    {
        $user = $request->user();

        try {
            $result = DB::transaction(function () use ($user) {
                $lockedUser = User::query()
                    ->whereKey($user->id)
                    ->lockForUpdate()
                    ->firstOrFail();

                $today = Carbon::today();
                $todayString = $today->toDateString();

                $exists = DB::table('user_sign_ins')
                    ->where('user_id', $lockedUser->id)
                    ->where('sign_date', $todayString)
                    ->lockForUpdate()
                    ->exists();

                if ($exists) {
                    throw new \RuntimeException('今天已经签到过了');
                }

                $yesterdaySign = DB::table('user_sign_ins')
                    ->where('user_id', $lockedUser->id)
                    ->where('sign_date', $today->copy()->subDay()->toDateString())
                    ->first();

                $continuousDays = $yesterdaySign
                    ? ((int) $yesterdaySign->continuous_days + 1)
                    : 1;

                $basePoints = max(0, (int) Setting::get('sign_in_points', 5));
                $bonusDays = max(0, (int) Setting::get('sign_in_bonus_days', 7));
                $continuousBonus = max(0, (int) Setting::get('sign_in_continuous_bonus', 20));

                $bonusPoints = ($bonusDays > 0 && $continuousBonus > 0 && $continuousDays % $bonusDays === 0)
                    ? $continuousBonus
                    : 0;

                $pointsGained = $basePoints + $bonusPoints;
                $beforePoints = (int) $lockedUser->points;
                $afterPoints = $beforePoints + $pointsGained;

                $signId = DB::table('user_sign_ins')->insertGetId([
                    'user_id' => $lockedUser->id,
                    'points_gained' => $pointsGained,
                    'sign_date' => $todayString,
                    'continuous_days' => $continuousDays,
                    'created_at' => now(),
                ]);

                $lockedUser->points = $afterPoints;
                $lockedUser->save();

                DB::table('point_logs')->insert([
                    'user_id' => $lockedUser->id,
                    'type' => 'sign_in',
                    'action' => 1,
                    'points' => $pointsGained,
                    'before_points' => $beforePoints,
                    'after_points' => $afterPoints,
                    'target_id' => $signId,
                    'target_type' => 'user_sign_in',
                    'description' => $bonusPoints > 0
                        ? '签到奖励：+' . $basePoints . '，连续奖励：+' . $bonusPoints
                        : '每日签到：+' . $basePoints,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                return [
                    'points_gained' => $pointsGained,
                    'continuous_days' => $continuousDays,
                    'user' => $lockedUser->fresh(),
                ];
            });
        } catch (\RuntimeException $e) {
            return $this->fail($e->getMessage(), 409);
        }

        $freshUser = $result['user'];

        return $this->ok([
            'points_gained' => $result['points_gained'],
            'continuous_days' => $result['continuous_days'],
            'user' => $this->userPayload($freshUser),
        ], "签到成功，获得 {$result['points_gained']} 积分，已连续签到 {$result['continuous_days']} 天");
    }

    public function downloads(Request $request): JsonResponse
    {
        $user = $request->user();
        $perPage = min(50, max(1, $request->integer('per_page', 20)));
        $page = max(1, $request->integer('page', 1));

        $paginator = DB::table('download_logs')
            ->leftJoin('apps', 'download_logs.app_id', '=', 'apps.id')
            ->where('download_logs.user_id', $user->id)
            ->select([
                'download_logs.id',
                'download_logs.app_id',
                'download_logs.points_spent',
                'download_logs.created_at',
                'apps.name as app_name',
                'apps.icon as app_icon',
                'apps.version as app_version',
                'apps.size as app_size',
                'apps.points_required as app_points_required',
            ])
            ->orderByDesc('download_logs.created_at')
            ->orderByDesc('download_logs.id')
            ->paginate($perPage, ['*'], 'page', $page);

        $items = collect($paginator->items())->map(function ($row) {
            $pointsSpent = (int) ($row->points_spent ?? 0);
            $appPoints = (int) ($row->app_points_required ?? 0);

            [$type, $label] = match (true) {
                $pointsSpent > 0 => ['points', '积分下载'],
                $appPoints <= 0 => ['free', '免费资源'],
                default => ['vip_free', '会员免费'],
            };

            return [
                'id' => (int) $row->id,
                'app_id' => (int) $row->app_id,
                'app_name' => (string) ($row->app_name ?? '资源已删除'),
                'app_icon' => $this->absoluteUrl($row->app_icon),
                'app_version' => (string) ($row->app_version ?: '1.0'),
                'app_size' => (string) ($row->app_size ?: '未知大小'),
                'points_spent' => $pointsSpent,
                'download_type' => $type,
                'download_type_label' => $label,
                'created_at' => $this->isoDate($row->created_at),
            ];
        })->values()->all();

        return $this->ok($this->paginated($paginator, $items));
    }

    public function points(Request $request): JsonResponse
    {
        $user = $request->user();
        $perPage = min(100, max(1, $request->integer('per_page', 30)));
        $page = max(1, $request->integer('page', 1));

        $paginator = PointLog::query()
            ->where('user_id', $user->id)
            ->orderByDesc('id')
            ->paginate($perPage, ['*'], 'page', $page);

        $items = collect($paginator->items())->map(fn (PointLog $log) => [
            'id' => (int) $log->id,
            'type' => (string) $log->type,
            'action' => (int) $log->action,
            'points' => (int) $log->points,
            'before_points' => (int) $log->before_points,
            'after_points' => (int) $log->after_points,
            'description' => (string) $log->description,
            'created_at' => $this->isoDate($log->created_at),
        ])->values()->all();

        return $this->ok(array_merge(
            $this->paginated($paginator, $items),
            ['current_points' => (int) $user->points]
        ));
    }

    public function notificationsCount(Request $request): JsonResponse
    {
        return $this->ok(['unread_count' => $this->unreadMessages((int) $request->user()->id)]);
    }

    /**
     * “赚取积分”页面：邀请链接 + 邀请统计。
     */
    public function invitations(Request $request): JsonResponse
    {
        $user = $request->user();

        $count = 0;
        $points = 0;

        if (Schema::hasTable('user_invitations')) {
            $count = (int) DB::table('user_invitations')
                ->where('inviter_id', $user->id)
                ->count();

            $points = (int) DB::table('user_invitations')
                ->where('inviter_id', $user->id)
                ->sum('reward_points');
        }

        return $this->ok([
            'invite_link' => url('/user/register?aff=' . $user->id),
            'count' => $count,
            'points' => $points,
        ]);
    }
}
