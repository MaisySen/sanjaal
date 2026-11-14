<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

class Post extends Model
{
    use SoftDeletes;

    protected $guarded = [];

    protected static function booted(): void
    {
        static::creating(fn (Post $p) => $p->public_id ??= (string) Str::uuid());
    }

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
    public function media(): HasMany { return $this->hasMany(PostMedia::class); }
    public function comments(): HasMany { return $this->hasMany(Comment::class); }
    public function hashtags(): BelongsToMany { return $this->belongsToMany(Hashtag::class); }
    public function likes(): HasMany { return $this->hasMany(Like::class); }
}
