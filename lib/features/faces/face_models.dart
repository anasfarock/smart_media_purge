import 'dart:typed_data';

class PersonCluster {
  const PersonCluster({
    required this.id,
    required this.name,
    required this.hidden,
    required this.locked,
    required this.faceCount,
    required this.photoCount,
    required this.thumb,
  });

  final int id;
  final String? name;
  final bool hidden;
  final bool locked;
  final int faceCount;
  final int photoCount;
  final Uint8List? thumb;

  String get displayName => (name == null || name!.isEmpty) ? 'Person $id' : name!;
}

class FaceRow {
  const FaceRow({
    required this.assetId,
    required this.album,
    required this.area,
    required this.embedding,
    required this.thumb,
  });

  final String assetId;
  final String album;
  final double area;
  final Uint8List embedding;
  final Uint8List thumb;
}
