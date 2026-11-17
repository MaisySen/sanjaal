/// Presentation of actual room state. Server connection is not another person
/// answering, and reconnection must remain visible over existing video tiles.
enum CallTransport { connecting, connected, reconnecting, disconnected }

class CallPresentation {
  const CallPresentation(this.status, {required this.mediaAvailable});
  final String status;
  final bool mediaAvailable;
}

CallPresentation presentCall({
  required CallTransport transport,
  required bool setupComplete,
  required int remoteCount,
  required bool previouslyConnected,
}) {
  if (!setupComplete)
    return const CallPresentation('Connecting...', mediaAvailable: false);
  return switch (transport) {
    CallTransport.reconnecting => const CallPresentation(
      'Reconnecting...',
      mediaAvailable: false,
    ),
    CallTransport.disconnected => CallPresentation(
      previouslyConnected
          ? 'Call disconnected. End this call and try again.'
          : 'Could not connect.',
      mediaAvailable: false,
    ),
    CallTransport.connecting => const CallPresentation(
      'Connecting...',
      mediaAvailable: false,
    ),
    CallTransport.connected => CallPresentation(
      remoteCount == 0 ? 'Waiting for others to join' : 'Connected',
      mediaAvailable: true,
    ),
  };
}
