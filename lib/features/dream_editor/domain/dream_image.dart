import 'dart:convert';

/// 图片只在数据库保存相对文件名与像素尺寸，不保存相册临时路径。
/// 沙盒绝对路径可能在升级/恢复时改变，由平台存储接口在使用时重新解析。
class DreamImage {
  const DreamImage({
    required this.fileName,
    required this.width,
    required this.height,
  });
  final String fileName;
  final int width;
  final int height;
  double get aspectRatio => width / height;

  Map<String, Object> toJson() => {
    'fileName': fileName,
    'width': width,
    'height': height,
  };

  static List<DreamImage> decode(String value) => List.unmodifiable(
    (jsonDecode(value) as List).map((item) {
      final map = item as Map<String, dynamic>;
      final name = map['fileName'] as String;
      final width = map['width'] as int;
      final height = map['height'] as int;
      // 读取损坏元数据必须报错，不能把有附件的一天默认为空再覆盖。
      if (!RegExp(r'^[a-zA-Z0-9_-]+\.img$').hasMatch(name) ||
          width <= 0 ||
          height <= 0) {
        throw const FormatException('Invalid image attachment');
      }
      return DreamImage(fileName: name, width: width, height: height);
    }),
  );
  static String encode(List<DreamImage> images) =>
      jsonEncode(images.map((e) => e.toJson()).toList());
}
