class NfoMetadataUpdate {
  const NfoMetadataUpdate({
    this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.rating,
    this.genre,
    this.externalId,
  });
  final String? title, originalTitle, overview, genre, externalId;
  final int? year;
  final double? rating;
}
