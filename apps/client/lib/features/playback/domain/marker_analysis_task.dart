import '../../../domain/media_source.dart';

enum MarkerAnalysisState { queued, running, completed, failed, cancelled }

/// BackgroundTaskSnapshot's markerAnalysis projection. No credentials, media
/// URLs, chapter names or raw exception messages are retained in task history.
class MarkerAnalysisTask {
  MarkerAnalysisTask({
    required this.id,
    required this.root,
    required String title,
    required this.startedAt,
    this.state = MarkerAnalysisState.queued,
    this.total = 0,
    this.processed = 0,
    this.createdCandidates = 0,
    this.skipped = 0,
    this.hidesDetail = false,
    this.error,
    this.finishedAt,
  }) : title = hidesDetail ? '片头片尾检测' : title;

  final String id, title;
  final MediaIdentity root;
  final MarkerAnalysisState state;
  final int total, processed, createdCandidates, skipped;
  final bool hidesDetail;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;
  bool get active =>
      state == MarkerAnalysisState.queued ||
      state == MarkerAnalysisState.running;
  bool get isCancellable => active;
  double? get progress => total == 0 ? null : (processed / total).clamp(0, 1);
  String get stateTitle => switch (state) {
    MarkerAnalysisState.queued => '等待中',
    MarkerAnalysisState.running => '进行中',
    MarkerAnalysisState.completed => '已完成',
    MarkerAnalysisState.failed => '有错误',
    MarkerAnalysisState.cancelled => '已取消',
  };
  String get detail => hidesDetail
      ? '条目、路径和文件名已隐藏'
      : switch (state) {
          MarkerAnalysisState.queued => '准备分析 $total 个视频的内嵌章节',
          MarkerAnalysisState.running => '已分析 $processed/$total 个视频',
          MarkerAnalysisState.completed =>
            createdCandidates > 0
                ? '新增 $createdCandidates 个待审核标记'
                : '没有发现可审核候选',
          MarkerAnalysisState.failed => error ?? '片头片尾检测失败，请重试。',
          MarkerAnalysisState.cancelled => '片头片尾检测已取消',
        };

  MarkerAnalysisTask copyWith({
    MarkerAnalysisState? state,
    int? processed,
    int? createdCandidates,
    int? skipped,
    bool? hidesDetail,
    String? error,
    DateTime? finishedAt,
  }) => MarkerAnalysisTask(
    id: id,
    root: root,
    title: title,
    startedAt: startedAt,
    state: state ?? this.state,
    total: total,
    processed: processed ?? this.processed,
    createdCandidates: createdCandidates ?? this.createdCandidates,
    skipped: skipped ?? this.skipped,
    hidesDetail: hidesDetail ?? this.hidesDetail,
    error: error ?? this.error,
    finishedAt: finishedAt ?? this.finishedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': root.sourceId,
    'localId': root.localId,
    'title': title,
    'state': state.name,
    'total': total,
    'processed': processed,
    'createdCandidates': createdCandidates,
    'skipped': skipped,
    'hidesDetail': hidesDetail,
    'error': error,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'finishedAt': finishedAt?.millisecondsSinceEpoch,
  };

  factory MarkerAnalysisTask.fromJson(Map<String, dynamic> json) {
    final total = json['total'] as int;
    final processed = json['processed'] as int;
    final created = json['createdCandidates'] as int;
    final skipped = json['skipped'] as int;
    if (total < 0 ||
        processed < 0 ||
        processed > total ||
        created < 0 ||
        skipped < 0) {
      throw const FormatException('Invalid marker task counts');
    }
    return MarkerAnalysisTask(
      id: json['id'] as String,
      root: (
        sourceId: json['sourceId'] as String,
        localId: json['localId'] as String,
      ),
      title: json['title'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        json['startedAt'] as int,
        isUtc: true,
      ),
      state: MarkerAnalysisState.values.byName(json['state'] as String),
      total: total,
      processed: processed,
      createdCandidates: created,
      skipped: skipped,
      hidesDetail: json['hidesDetail'] as bool,
      error: json['error'] as String?,
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['finishedAt'] as int,
              isUtc: true,
            ),
    );
  }
}
