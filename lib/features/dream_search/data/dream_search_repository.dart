import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 搜索是既有梦境的只读查询，不另外保存正文副本或搜索历史。
abstract interface class IDreamSearchRepository {
  /// 按正文中的连续关键词匹配，忽略关键词首尾空白和英文字母大小写。
  ///
  /// 中文、emoji、标点按字面匹配，% / _ 也只是普通字符；不支持正则、
  /// 拼音或分词。空关键词返回空列表，结果按梦境日期倒序，失败向上传递。
  Future<List<DreamEntry>> search(String keyword);
}
