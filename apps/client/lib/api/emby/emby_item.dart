import '../../domain/media_source.dart';

class EmbyItemPage {
  const EmbyItemPage(this.items, this.total);
  final List<EmbyItem> items;
  final int? total;
  factory EmbyItemPage.fromJson(Map<String, dynamic> json) {
    final raw = json['Items'];
    final total = json['TotalRecordCount'];
    if (raw is! List || (total != null && (total is! int || total < 0))) {
      throw const SourceFailure('Emby 媒体分页响应无效，已保留原索引。');
    }
    return EmbyItemPage(
      List.unmodifiable(
        raw.map((v) {
          if (v is! Map<String, dynamic>) {
            throw const SourceFailure('Emby 媒体条目无效。');
          }
          return EmbyItem.fromJson(v);
        }),
      ),
      total as int?,
    );
  }
}

class EmbyItem {
  EmbyItem._(this.data);
  final Map<String, dynamic> data;
  factory EmbyItem.fromJson(Map<String, dynamic> json) {
    for (final key in ['Id', 'Name', 'Type']) {
      if (json[key] is! String ||
          (key != 'Name' && (json[key] as String).trim().isEmpty)) {
        throw const SourceFailure('Emby 媒体条目缺少有效的标识或类型。');
      }
    }
    // Validate optional structures before any index replacement can commit.
    for (final key in ['UserData', 'ImageTags']) {
      if (json[key] != null && json[key] is! Map<String, dynamic>) {
        throw const SourceFailure('Emby 媒体元数据无效。');
      }
    }
    for (final key in [
      'MediaSources',
      'Genres',
      'Artists',
      'BackdropImageTags',
    ]) {
      if (json[key] != null && json[key] is! List) {
        throw const SourceFailure('Emby 媒体元数据无效。');
      }
    }
    return EmbyItem._(Map.unmodifiable(json));
  }
  String get id => data['Id'] as String;
  String get name => data['Name'] as String;
  String get type => (data['Type'] as String).toLowerCase();
  String? text(String key) => data[key] as String?;
  int? integer(String key) => data[key] as int?;
  Map<String, dynamic> get userData =>
      (data['UserData'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get mediaSource {
    final sources = data['MediaSources'] as List?;
    return sources == null || sources.isEmpty
        ? const {}
        : sources.first as Map<String, dynamic>;
  }

  bool get hasPoster => (data['ImageTags'] as Map?)?['Primary'] != null;
  bool get hasBackdrop =>
      (data['BackdropImageTags'] as List?)?.isNotEmpty ?? false;
}
