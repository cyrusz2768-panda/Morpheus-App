import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认数据库连接在应用支持目录创建文件，后台连接关闭后重开仍能读取', () async {
    // 其他仓库测试传入 NativeDatabase(file)，适合验证 SQL，但会跳过 AppDatabase
    // 的默认连接分支。本测试故意调用无参数的 AppDatabase()，让真实的
    // drift_flutter 路径解析、后台 isolate 和 SQLite 文件连接全部运行。
    final directory = await Directory.systemTemp.createTemp(
      'morpheus_default_connection_test_',
    );
    final supportDirectory = Directory('${directory.path}/support');
    final cacheDirectory = Directory('${directory.path}/cache');
    final pathProvider = _TestPathProvider(
      supportDirectory: supportDirectory,
      cacheDirectory: cacheDirectory,
    );

    // 只替换“系统会返回哪个目录”，不替换数据库或 Repository 实现。
    // 新版 path_provider 在部分平台通过 FFI 而非 MethodChannel 获取路径，
    // 因此直接替换其平台接口，比只拦截一个插件通道更可靠。
    // 此处必须在构造数据库之前完成，避免测试碰到用户真实的 App 支持目录。
    final originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = pathProvider;

    final date = DateTime(2026, 11, 3);
    final savedAt = DateTime.utc(2026, 11, 3, 12, 34, 56, 789);
    const dream = '不是内存缓存，而是磁盘上的梦境。🌙\n关闭连接后仍应存在。';
    final file = File('${supportDirectory.path}/nightwalker.sqlite');

    try {
      // 第一阶段走 App 的默认打开方式，而不是向构造函数注入测试连接。
      final firstDatabase = AppDatabase();
      try {
        final repository = DriftDreamRepository(
          firstDatabase,
          now: () => savedAt,
        );
        final saved = await repository.save(date: date, content: dream);

        expect(saved.content, dream);
        expect(saved.createdAt, savedAt);
        expect(pathProvider.supportRequests, 1);
        expect(pathProvider.cacheRequests, greaterThanOrEqualTo(1));
        expect(await file.exists(), isTrue);
        expect(await file.length(), greaterThan(0));
      } finally {
        // 必须 await 连接关闭，再用新实例打开同一文件；不能只销毁 Dart 变量。
        // 这也让后台 isolate 有机会释放 SQLite 文件句柄。
        await firstDatabase.close();
      }

      // 第二阶段再次调用默认构造函数，确认没有依赖第一份连接的内存状态。
      final reopenedDatabase = AppDatabase();
      try {
        final repository = DriftDreamRepository(reopenedDatabase);
        final restored = await repository.getByDate(date);

        expect(restored, isNotNull);
        expect(restored!.id, '2026-11-03');
        expect(restored.content, dream);
        expect(restored.createdAt, savedAt);
        expect(restored.updatedAt, savedAt);
        expect(pathProvider.supportRequests, 2);
        expect(
          await reopenedDatabase.select(reopenedDatabase.dreamRecords).get(),
          hasLength(1),
        );
      } finally {
        await reopenedDatabase.close();
      }
    } finally {
      // 平台接口是全局状态，使用结束后还原，防止影响同一测试进程的其他代码。
      // 只删除本测试随机创建的目录；正式数据库路径和用户文件从未被使用。
      PathProviderPlatform.instance = originalPathProvider;
      await directory.delete(recursive: true);
    }
  });
}

/// 在系统插件与应用之间提供可控路径；没有模拟数据库行为。
///
/// 使用 extends 而非 implements，沿用平台接口的身份校验和其他默认方法。
/// 两种路径都位于同一个随机临时目录下，测试结束后可以完整清理。
class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider({
    required this.supportDirectory,
    required this.cacheDirectory,
  });

  final Directory supportDirectory;
  final Directory cacheDirectory;
  int supportRequests = 0;
  int cacheRequests = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    supportRequests += 1;
    // 真正的平台插件会保证应用支持目录存在；测试替身也遵守同样契约。
    await supportDirectory.create(recursive: true);
    return supportDirectory.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    cacheRequests += 1;
    // drift_flutter 会把 SQLite 临时文件指向这里，但正式数据库仍在 support。
    // 两者分开，避免误把“保存到临时缓存”也当成持久化测试通过。
    await cacheDirectory.create(recursive: true);
    return cacheDirectory.path;
  }
}
