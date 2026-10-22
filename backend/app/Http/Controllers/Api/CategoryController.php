<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\RespondsWithJson;
use App\Http\Controllers\Controller;
use App\Models\Category;
use Illuminate\Http\JsonResponse;

class CategoryController extends Controller
{
    use RespondsWithJson;

    public function index(): JsonResponse
    {
        $mainCategories = Category::query()
            ->whereNull('parent_id')
            ->orderBy('id')
            ->get();

        $items = $mainCategories->map(function (Category $category) {
            $children = $category->children()
                ->orderBy('id')
                ->withCount(['apps' => fn ($query) => $query->where('is_active', 1)])
                ->get();

            $childPayload = $children->map(fn (Category $child) => [
                'id' => (int) $child->id,
                'name' => (string) $child->name,
                'slug' => (string) $child->slug,
                'parent_id' => (int) $category->id,
                'apps_count' => (int) $child->apps_count,
                'children' => [],
            ])->values()->all();

            return [
                'id' => (int) $category->id,
                'name' => (string) $category->name,
                'slug' => (string) $category->slug,
                'parent_id' => null,
                'apps_count' => $children->sum('apps_count'),
                'children' => $childPayload,
            ];
        })->values()->all();

        return $this->ok($items);
    }
}
