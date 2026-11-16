<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class Conversation extends Model
{
    protected $guarded = [];

    protected function casts(): array
    {
        return ['last_message_at' => 'datetime'];
    }

    protected static function booted(): void
    {
        static::creating(fn (Conversation $c) => $c->public_id ??= (string) Str::uuid());
    }

    public function members(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'conversation_members')->withPivot('role', 'last_read_message_id', 'pinned', 'muted', 'archived', 'history_from_id')->withTimestamps();
    }

    public function messages(): HasMany { return $this->hasMany(Message::class); }

    public function hasMember(User $user): bool
    {
        return $this->members()->where('users.id', $user->id)->exists();
    }
}
