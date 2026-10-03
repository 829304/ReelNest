class LibraryCategory {
  const LibraryCategory({
    required this.id,
    required this.title,
    required this.itemCount,
  });

  final String id;
  final String title;
  final int itemCount;
}

class LibraryCatalog {
  LibraryCatalog({
    required List<LibraryCategory> categories,
    required this.videoGroupItemCount,
    required this.fetchedAt,
  }) : categories = List.unmodifiable(categories);

  final List<LibraryCategory> categories;
  // This count excludes episodes; it is not a sum of category item counts.
  final int videoGroupItemCount;
  final DateTime fetchedAt;
}
