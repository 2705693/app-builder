class ParseResult {
  final String platform;
  final String type; // 'video' 或 'images' / 'image'
  final String title;
  final String author;
  final String coverUrl;
  final String videoUrl;
  final String originUrl;
  final List<String> images;

  ParseResult({
    required this.platform,
    required this.type,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.videoUrl,
    required this.originUrl,
    required this.images,
  });

  factory ParseResult.fromJson(Map<String, dynamic> json) {
    var rawImages = json['images'];
    List<String> imgList = [];
    if (rawImages is List) {
      imgList = rawImages.map((e) => e.toString()).toList();
    }

    String typeStr = (json['type'] ?? 'video').toString();
    if (imgList.isNotEmpty && typeStr != 'video') {
      typeStr = 'images';
    }

    return ParseResult(
      platform: json['platform'] ?? '未知平台',
      type: typeStr,
      title: json['title'] ?? '无标题媒体',
      author: json['author'] ?? '创作者',
      coverUrl: json['cover_url'] ?? json['cover'] ?? '',
      videoUrl: json['video_url'] ?? '',
      originUrl: json['origin_url'] ?? '',
      images: imgList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      'type': type,
      'title': title,
      'author': author,
      'cover_url': coverUrl,
      'video_url': videoUrl,
      'origin_url': originUrl,
      'images': images,
    };
  }
}
