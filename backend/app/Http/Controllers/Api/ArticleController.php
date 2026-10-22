<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\PresentsUser;
use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Models\Post;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ArticleController extends Controller
{
    use PresentsUser, RespondsWithJson;

    public function index(Request $request): JsonResponse
    {
        $perPage = min(50, max(1, $request->integer('per_page', 15)));
        $page = max(1, $request->integer('page', 1));

        $paginator = Post::query()
            ->published()
            ->orderBy('sort')
            ->latest('published_at')
            ->latest('id')
            ->paginate($perPage, ['*'], 'page', $page);

        $items = collect($paginator->items())
            ->map(fn (Post $post) => $this->summary($post))
            ->values()
            ->all();

        return $this->ok($this->paginated($paginator, $items));
    }

    public function show(Post $post): JsonResponse
    {
        if (! $post->is_published) {
            return $this->fail('文章不存在或尚未发布', 404);
        }

        if ($post->published_at && $post->published_at->isFuture()) {
            return $this->fail('文章不存在或尚未发布', 404);
        }

        Post::withoutTimestamps(function () use ($post) {
            $post->increment('views');
        });

        $prevPost = Post::query()
            ->published()
            ->where('id', '<', $post->id)
            ->orderByDesc('id')
            ->first();

        $nextPost = Post::query()
            ->published()
            ->where('id', '>', $post->id)
            ->orderBy('id')
            ->first();

        return $this->ok([
            'id' => (int) $post->id,
            'title' => (string) $post->title,
            'summary' => $post->summary ?: $this->plainText($post->content, 120),
            'cover' => $this->absoluteUrl($post->cover),
            'content' => (string) $post->content,
            'views' => (int) $post->views + 1,
            'sort' => (int) $post->sort,
            'published_at' => $this->isoDate($post->published_at),
            'created_at' => $this->isoDate($post->created_at),
            'updated_at' => $this->isoDate($post->updated_at),
            'prev' => $prevPost ? ['id' => (int) $prevPost->id, 'title' => (string) $prevPost->title] : null,
            'next' => $nextPost ? ['id' => (int) $nextPost->id, 'title' => (string) $nextPost->title] : null,
        ]);
    }

    private function summary(Post $post): array
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
