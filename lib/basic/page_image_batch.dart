class JmPageImageRequest {
  final int id;
  final String imageName;
  const JmPageImageRequest(this.id, this.imageName);
  Map<String, dynamic> toJson() => {'id': id, 'image_name': imageName};
}

class JmPageImageBatchItem {
  final int id;
  final String? path;
  final int? width;
  final int? height;
  final String? error;
  const JmPageImageBatchItem({required this.id, this.path, this.width, this.height, this.error});
  factory JmPageImageBatchItem.fromJson(Map value) => JmPageImageBatchItem(
        id: (value['id'] as num?)?.toInt() ?? 0,
        path: value['path'] as String?,
        width: (value['width'] as num?)?.toInt(),
        height: (value['height'] as num?)?.toInt(),
        error: value['error'] as String?,
      );
}
