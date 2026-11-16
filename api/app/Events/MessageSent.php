<?php

namespace App\Events;

use App\Models\Message;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class MessageSent implements ShouldBroadcastNow
{
    use Dispatchable, SerializesModels;

    public function __construct(public Message $message) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('conversation.'.$this->message->conversation->public_id)];
    }

    public function broadcastAs(): string { return 'message.sent'; }

    public function broadcastWith(): array
    {
        // One payload goes to every member, so a reply preview is only included when it points at a message every member may see.
        $hidden = (int) \Illuminate\Support\Facades\DB::table('conversation_members')->where('conversation_id', $this->message->conversation_id)->max('history_from_id');

        return ['message' => \App\Http\Resources\Present::message($this->message->loadMissing('user', 'conversation'), $hidden)];
    }
}
