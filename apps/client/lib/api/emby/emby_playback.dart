/// EmbyService.reportPlayback phases. A session ID lasts for one decoded item.
enum EmbyPlaybackPhase { started, progress, stopped }

/// Ephemeral authenticated resource; never persist or send over window channels.
class EmbyPlaybackResource {
  const EmbyPlaybackResource(this.uri, this.mediaSourceId);
  final Uri uri;
  final String? mediaSourceId;
  @override
  String toString() => 'EmbyPlaybackResource';
}
