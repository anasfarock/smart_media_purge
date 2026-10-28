import 'package:photo_manager/photo_manager.dart';

class MediaService {
  Future<bool> ensurePermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.hasAccess;
  }

  /// All images on the device, newest first.
  Future<List<AssetEntity>> loadImages() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (paths.isEmpty) return [];
    final all = paths.first;
    final count = await all.assetCountAsync;
    return all.getAssetListRange(start: 0, end: count);
  }
}
