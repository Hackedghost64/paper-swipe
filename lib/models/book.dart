class Book {
  final String id;
  final String title;
  final String pdfPath;
  final String thumbnailPath;
  final int currentPage;
  final int totalPages;
  final DateTime lastReadAt;

  Book({
    required this.id,
    required this.title,
    required this.pdfPath,
    required this.thumbnailPath,
    required this.currentPage,
    required this.totalPages,
    required this.lastReadAt,
  });

  double get progress {
    if (totalPages <= 0) return 0.0;
    final val = (currentPage + 1) / totalPages;
    return val.clamp(0.0, 1.0);
  }

  int get progressPercent {
    return (progress * 100).round();
  }

  Book copyWith({
    String? id,
    String? title,
    String? pdfPath,
    String? thumbnailPath,
    int? currentPage,
    int? totalPages,
    DateTime? lastReadAt,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      pdfPath: pdfPath ?? this.pdfPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'pdfPath': pdfPath,
      'thumbnailPath': thumbnailPath,
      'currentPage': currentPage,
      'totalPages': totalPages,
      'lastReadAt': lastReadAt.toIso8601String(),
    };
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      title: json['title'] as String,
      pdfPath: json['pdfPath'] as String,
      thumbnailPath: json['thumbnailPath'] as String,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.tryParse(json['lastReadAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
