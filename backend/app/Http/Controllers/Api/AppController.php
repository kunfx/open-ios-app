<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\PresentsUser;
use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Http\Controllers\DownloadController as WebDownloadController;
use App\Models\App as ResourceApp;
use App\Models\Category;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\URL;

class AppController extends Controller
{
    use PresentsUser, RespondsWithJson;

    public function index(Request $request): JsonResponse
    {
        $query = ResourceApp::query()
            ->where('is_active', 1)
            ->with(['category.parent']);

        $keyword = trim((string) $request->query('q', ''));

        if ($keyword !== '') {
            $query->where(function ($sub) use ($keyword) {
                $like = '%' . $keyword . '%';

                $sub->where('name', 'like', $like)
                    ->orWhere('name_en', 'like', $like)
                    ->orWhere('short_description', 'like', $like)
                    ->orWhere('description', 'like', $like);
            });
        }

        if ($request->filled('category_id')) {
            $query->where('category_id', $request->integer('category_id'));
        } elseif ($request->filled('main')) {
            $main = Category::query()
                ->where('slug', (string) $request->query('main'))
                ->whereNull('parent_id')
                ->first();

            if (! $main) {
                return $this->fail('分类不存在', 404);
            }

            $ids = $main->children()->pluck('id')->push($main->id);
            $query->whereIn('category_id', $ids);
        }

        switch ((string) $request->query('sort', 'latest')) {
            case 'popular':
                $query->orderByDesc('views')->orderByDesc('id');
                break;
            case 'points':
                $query->orderByDesc('points_required')->orderByDesc('id');
                break;
            case 'name':
                $query->orderBy('name');
                break;
            default:
                $query->latest('updated_at')->latest('id');
                break;
        }

        $perPage = min(50, max(1, $request->integer('per_page', 20)));
        $page = max(1, $request->integer('page', 1));
        $paginator = $query->paginate($perPage, ['*'], 'page', $page);

        $items = collect($paginator->items())
            ->map(fn (ResourceApp $app) => $this->summary($app))
            ->values()
            ->all();

        return $this->ok($this->paginated($paginator, $items));
    }

    public function show(Request $request, ResourceApp $app): JsonResponse
    {
        if (! $app->is_active) {
            return $this->fail('资源不存在或已下架', 404);
        }

        // 与网站详情页保持一致：浏览数 +1，但不改 updated_at
        DB::table('apps')->where('id', $app->id)->increment('views');
        $app->views = (int) $app->views + 1;
        $app->load('category.parent');

        $user = $request->user();
        $unlocked = false;

        if ($user) {
            $unlocked = DB::table('download_logs')
                ->where('user_id', $user->id)
                ->where('app_id', $app->id)
                ->exists();
        }

        $screenshots = array_values(array_filter(array_map(
            fn ($value) => $this->absoluteUrl(trim($value)),
            preg_split('/[\r\n,]+/', (string) $app->screenshots) ?: []
        )));

        $downloadLinks = collect($this->rawDownloadLinks($app))
            ->map(fn (array $link) => [
                // 注意：这里绝不返回真实下载地址，必须由已登录用户走下载接口获取签名地址
                'title' => (string) ($link['title'] ?? '下载'),
                'type' => (string) ($link['type'] ?? '下载'),
                'remark' => (string) ($link['remark'] ?? ''),
            ])
            ->values()
            ->all();

        return $this->ok([
            'id' => (int) $app->id,
            'name' => (string) $app->name,
            'name_en' => $app->name_en,
            'icon' => $this->absoluteUrl($app->icon),
            'version' => (string) ($app->version ?: '1.0'),
            'size' => (string) ($app->size ?: '未知大小'),
            'points_required' => (int) ($app->points_required ?? 0),
            'is_free' => (int) ($app->points_required ?? 0) <= 0,
            'short_description' => $app->short_description,
            'description' => $app->description,
            'description_en' => $app->description_en,
            'mod_info' => $app->mod_info,
            'mod_info_en' => $app->mod_info_en,
            'screenshots' => $screenshots,
            'download_links' => $downloadLinks,
            'unlocked' => $unlocked,
            'views' => (int) $app->views,
            'category' => $this->categoryRef($app->category),
            'main_category' => $this->categoryRef($app->category?->parent),
            'created_at' => $this->isoDate($app->created_at),
            'updated_at' => $this->isoDate($app->updated_at),
        ]);
    }

    /**
     * 下载第一步：复用网站 DownloadController 的积分/免费额度/VIP 判断逻辑。
     */
    public function download(Request $request, ResourceApp $app): JsonResponse
    {
        $request->merge(['app_id' => $app->id]);

        $response = app(WebDownloadController::class)->requestDownload($request);

        return $this->rewriteDownloadResponse($response, $app, $request);
    }

    /**
     * 下载第二步：付费资源确认扣除积分（同样复用网站逻辑）。
     */
    public function confirmDownload(Request $request, ResourceApp $app): JsonResponse
    {
        $request->merge(['app_id' => $app->id]);

        $response = app(WebDownloadController::class)->confirmDownload($request);

        return $this->rewriteDownloadResponse($response, $app, $request);
    }

    private function summary(ResourceApp $app): array
    {
        return [
            'id' => (int) $app->id,
            'name' => (string) $app->name,
            'name_en' => $app->name_en,
            'icon' => $this->absoluteUrl($app->icon),
            'version' => (string) ($app->version ?: '1.0'),
            'size' => (string) ($app->size ?: '未知大小'),
            'points_required' => (int) ($app->points_required ?? 0),
            'is_free' => (int) ($app->points_required ?? 0) <= 0,
            'short_description' => $app->short_description,
            'views' => (int) ($app->views ?? 0),
            'category' => $this->categoryRef($app->category),
            'main_category' => $this->categoryRef($app->category?->parent),
            'created_at' => $this->isoDate($app->created_at),
            'updated_at' => $this->isoDate($app->updated_at),
        ];
    }

    /**
     * 把网站返回的“2 小时临时下载链接”替换成 iOS API 的签名链接。
     */
    private function rewriteDownloadResponse(JsonResponse $response, ResourceApp $app, Request $request): JsonResponse
    {
        $payload = $response->getData(true);

        if (! empty($payload['download_links']) && is_array($payload['download_links'])) {
            foreach ($payload['download_links'] as $index => &$link) {
                if (! is_array($link)) {
                    continue;
                }

                $relativePath = URL::temporarySignedRoute(
                    'api.download.file',
                    now()->addHours(2),
                    ['app' => $app->id, 'index' => $index],
                    absolute: false
                );

                // path 让 App 可以拼自己的域名；url 作为兼容字段
                $link['path'] = $relativePath;
                $link['url'] = $request->getSchemeAndHttpHost() . $relativePath;
            }
            unset($link);
        }

        return response()->json($payload, $response->getStatusCode());
    }

    private function rawDownloadLinks(ResourceApp $app): array
    {
        $links = $app->download_links;

        if (is_string($links)) {
            $links = json_decode($links, true);
        }

        return is_array($links) ? array_values($links) : [];
    }
}
