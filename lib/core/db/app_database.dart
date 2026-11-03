import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:morpheus/core/db/tables/dream_records.dart';
import 'package:path_provider/path_provider.dart';

// part 表示这两个 Dart 文件共同组成一个库，允许生成器扩展当前数据库类。
// 首次运行 build_runner 后就会出现这个文件；它也会随项目一起提交到 Git。
part 'app_database.g.dart';

/// 应用唯一的数据库入口，集中管理连接、表定义和数据库版本。
///
/// 类似 C++ 中持有数据库连接的对象，但底层平台路径和 SQLite 连接由
/// drift_flutter 管理。连接会异步打开，构造函数不会同步等待磁盘 IO；查询会
/// 等待连接准备完成。SQL 在后台 isolate 中执行，避免让页面承担同步数据库工作。
@DriftDatabase(tables: [DreamRecords])
class AppDatabase extends _$AppDatabase {
  /// 正常运行不传参数，使用 App 私有目录中的持久化数据库。
  ///
  /// 测试可以传 NativeDatabase.memory() 或真实临时文件连接，从而测试同一套
  /// SQL / Repository 逻辑，而不依赖模拟器、path_provider 或用户的真实数据。
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// 当前第一版数据库结构。将来增加列时需要升级版本并编写迁移，不能通过
  /// 删除数据库来“解决”升级问题，否则真实用户保存的梦境就会丢失。
  @override
  int get schemaVersion => 1;

  /// 第一次打开空数据库时执行建表；已经存在的同版本文件不会被清空。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'nightwalker',
      native: const DriftNativeOptions(
        // 这个目录属于当前 App 的沙盒，不是源码目录，也不是临时缓存目录。
        // Android / iOS 的真实绝对路径不同，由系统提供；最终文件为
        // nightwalker.sqlite。普通退出、重启不会删除它，卸载/清除数据则会。
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
