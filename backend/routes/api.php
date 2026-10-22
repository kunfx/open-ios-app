<?php

use App\Http\Controllers\Api\AppController;
use App\Http\Controllers\Api\ArticleController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CategoryController;
use App\Http\Controllers\Api\DownloadLinkController;
use App\Http\Controllers\Api\HomeController;
use App\Http\Controllers\Api\MessageController;
use App\Http\Controllers\Api\UserController;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| iOS App API
|--------------------------------------------------------------------------
| 这个文件由 ios-app/backend 提供，复制到网站根目录的 routes/api.php。
| bootstrap/app.php 里需要增加：api: __DIR__.'/../routes/api.php'
|
| 所有 /api 前缀由 Laravel 自动添加，这里不要再写 prefix('api')。
*/

// 兼容 Laravel 默认的 api 限流器（某些版本 api 中间件组会带 throttle:api）
RateLimiter::for('api', function (Request $request) {
    return Limit::perMinute(120)->by($request->user()?->id ?: $request->ip());
});

Route::get('/health', fn () => response()->json([
    'success' => true,
    'data' => [
        'status' => 'ok',
        'name' => 'ios-resource-app-api',
        'time' => now()->toIso8601String(),
    ],
]));

Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:10,1');
Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:5,1');

/*
|--------------------------------------------------------------------------
| 公开接口（可选登录）
|--------------------------------------------------------------------------
| api.token:0 表示：带了有效 Bearer token 就识别用户，不带也能访问。
| 这样详情页可以显示“是否已解锁”，首页/分类/搜索无需登录。
*/
Route::middleware(['api.token:0', 'throttle:60,1'])->group(function () {
    Route::get('/home', [HomeController::class, 'index']);
    Route::get('/apps', [AppController::class, 'index']);
    Route::get('/apps/{app}', [AppController::class, 'show'])->whereNumber('app');
    Route::get('/categories', [CategoryController::class, 'index']);
    Route::get('/articles', [ArticleController::class, 'index']);
    Route::get('/articles/{post}', [ArticleController::class, 'show'])->whereNumber('post');
});

/*
|--------------------------------------------------------------------------
| 需要登录的接口
|--------------------------------------------------------------------------
*/
Route::middleware(['api.token', 'throttle:60,1'])->group(function () {
    Route::get('/user/profile', [UserController::class, 'profile']);
    Route::post('/user/profile', [UserController::class, 'updateProfile']);
    Route::post('/user/sign-in', [UserController::class, 'signIn']);
    Route::get('/user/downloads', [UserController::class, 'downloads']);
    Route::get('/user/points', [UserController::class, 'points']);
    Route::get('/user/invitations', [UserController::class, 'invitations']);
    Route::get('/user/messages/count', [UserController::class, 'notificationsCount']);

    Route::get('/messages', [MessageController::class, 'index']);
    Route::post('/messages/read-all', [MessageController::class, 'markAllRead']);
    Route::post('/messages/{id}/read', [MessageController::class, 'markRead']);

    // 下载：服务端判断积分 / VIP / 每日免费额度
    Route::post('/apps/{app}/download', [AppController::class, 'download'])->whereNumber('app');
    Route::post('/apps/{app}/download/confirm', [AppController::class, 'confirmDownload'])->whereNumber('app');

    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);
});

/*
|--------------------------------------------------------------------------
| 下载跳转（Laravel 签名校验，2 小时有效）
|--------------------------------------------------------------------------
| 该路由不要求 Bearer token，但必须持有下载接口返回的签名链接。
*/
Route::get('/download/{app}/{index}', [DownloadLinkController::class, 'redirect'])
    ->whereNumber('app')
    ->whereNumber('index')
    ->name('api.download.file');
