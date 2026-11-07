class HistoryItem {
  final String id;
  final String platform;
  final String type;
  final String title;
  final String coverUrl;
  final String videoUrl;
  final List<String> images;
  final DateTime createdAt;

  HistoryItem({
    required this.id,
    required this.platform,
    required this.type,
    required this.title,
    required this.coverUrl,
    required this.videoUrl,
    required this.images,
    required this.createdAt,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id'] ?? '',
      platform: json['platform'] ?? '',
      type: json['type'] ?? 'video',
      title: json['title'] ?? '',
      coverUrl: json['cover_url'] ?? '',
      videoUrl: json['video_url'] ?? '',
      images: (json['images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'platform': platform,
      'type': type,
      'title': title,
      'cover_url': coverUrl,
      'video_url': videoUrl,
      'images': images,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
