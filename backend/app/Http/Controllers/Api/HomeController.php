<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\PresentsUser;
use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Models\App as ResourceApp;
use App\Models\Category;
use App\Models\Post;
use Illuminate\Http\JsonResponse;

class HomeController extends Controller
{
    use PresentsUser, RespondsWithJson;

    public function index(): JsonResponse
    {
        $mainCategories = Category::query()
            ->whereNull('parent_id')
            ->whereIn('name', ['应用', '游戏', '巨魔'])
            ->get()
            ->keyBy('name');

        $apps = $this->appsForCategory($mainCategories->get('应用'), 9);
        $games = $this->appsForCategory($mainCategories->get('游戏'), 9);
        $trolls = $this->appsForCategory($mainCategories->get('巨魔'), 9);

        $featured = ResourceApp::query()
            ->where('is_active', 1)
            ->with(['category.parent'])
            ->latest('updated_at')
            ->limit(10)
            ->get()
            ->map(fn (ResourceApp $app) => $this->summary($app))
            ->values()
            ->all();

        $articles = Post::query()
            ->published()
            ->orderBy('sort')
            ->latest('published_at')
            ->latest('id')
            ->limit(6)
            ->get()
            ->map(fn (Post $post) => $this->articleSummary($post))
            ->values()
            ->all();

        $categories = $mainCategories->values()->map(fn (Category $category) => [
            'id' => (int) $category->id,
            'name' => (string) $category->name,
            'slug' => (string) $category->slug,
            'parent_id' => null,
            'apps_count' => 0,
            'children' => [],
        ])->all();

        return $this->ok([
            'featured' => $featured,
            'apps' => $apps,
            'games' => $games,
            'trolls' => $trolls,
            'articles' => $articles,
            'categories' => $categories,
        ]);
    }

    private function appsForCategory(?Category $category, int $limit): array
    {
        if (! $category) {
            return [];
        }

        $categoryIds = $category->children()->pluck('id')->push($category->id);

        return ResourceApp::query()
            ->whereIn('category_id', $categoryIds)
            ->where('is_active', 1)
            ->with(['category.parent'])
            ->latest('updated_at')
            ->limit($limit)
            ->get()
            ->map(fn (ResourceApp $app) => $this->summary($app))
            ->values()
            ->all();
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

    private function articleSummary(Post $post): array
    {
        return [
            'id' => (int) $post->id,
            'title' => (string) $post->title,
            'summary' => $post->summary ?: $this->plainText($post->content, 90),
            'cover' => $this->absoluteUrl($post->cover),
            'views' => (int) ($post->views ?? 0),
            'published_at' => $this->isoDate($post->published_at),
            'created_at' => $this->isoDate($post->created_at),
        ];
    }
}
