import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';

void main() {
  group('DriftDreamRepository 的基本存储契约', () {
    late AppDatabase database;
    late DriftDreamRepository repository;
    late DateTime currentTime;

    setUp(() {
      // 每个测试使用一份全新的内存 SQLite 数据库，而不是应用正式使用的文件。
      // 它仍会执行真正的 SQL、主键约束与事务，只是不保留到磁盘，测试速度更快。
      database = AppDatabase(NativeDatabase.memory());

      // 注入时钟，避免断言依赖“现在过了多少毫秒”而变得不稳定。
      // 保留一个可变变量，后面的更新测试可以明确模拟时间向前推进。
      currentTime = DateTime.utc(2026, 11, 3, 1, 2, 3, 456);
      repository = DriftDreamRepository(database, now: () => currentTime);
    });

    tearDown(() async {
      // 关闭连接很重要：测试不应把数据库句柄、流或后台任务留给下一个测试。
      await database.close();
    });

    test('没有记录的日期返回 null，不会凭空创建空记录', () async {
      final entry = await repository.getByDate(DateTime(2026, 11, 3));

      expect(entry, isNull);
      expect(await database.select(database.dreamRecords).get(), isEmpty);
    });

    test('空数据库读取历史返回空列表，不创建空记录', () async {
      expect(await repository.getAll(), isEmpty);
      expect(await database.select(database.dreamRecords).get(), isEmpty);
    });

    test('历史按梦境日期倒序，乱序插入及跨年不会打乱顺序', () async {
      // 保存顺序与日期顺序故意不同，验证的是 SQL 排序，而不是主键或插入顺序。
      await repository.save(date: DateTime(2026, 1, 2), content: '最早的梦');
      await repository.save(date: DateTime(2027, 1, 1), content: '最新的梦');
      await repository.save(date: DateTime(2026, 12, 31), content: '跨年前的梦');

      final history = await repository.getAll();

      expect(history.map((entry) => entry.id), [
        '2027-01-01',
        '2026-12-31',
        '2026-01-02',
      ]);
      expect(history.map((entry) => entry.content), ['最新的梦', '跨年前的梦', '最早的梦']);
    });

    test('补充旧梦境不重复，也不会因更新时间较新而排到历史首位', () async {
      final oldDate = DateTime(2026, 11, 2);
      await repository.save(date: oldDate, content: '旧日期的第一版');
      await repository.save(date: DateTime(2026, 11, 3), content: '最近一天的梦');
      currentTime = currentTime.add(const Duration(hours: 1));
      await repository.save(date: oldDate, content: '旧日期补充后的正文');

      final history = await repository.getAll();

      expect(history, hasLength(2));
      expect(history.first.id, '2026-11-03');
      expect(history.last.id, '2026-11-02');
      expect(history.last.content, '旧日期补充后的正文');
      expect(history.last.updatedAt.isAfter(history.first.updatedAt), isTrue);
    });

    test('删除记录后，历史只移除所选日期，其他日期保持不变', () async {
      final removedDate = DateTime(2026, 11, 2);
      await repository.save(date: removedDate, content: '即将删除');
      await repository.save(date: DateTime(2026, 11, 3), content: '需要保留');
      await repository.deleteByDate(removedDate);

      final history = await repository.getAll();

      expect(history, hasLength(1));
      expect(history.single.id, '2026-11-03');
      expect(history.single.content, '需要保留');
    });

    test('历史过滤旧的纯空白行，但完整保留有效正文的空白', () async {
      // 正常 save 已拒绝纯空白；直接写入测试数据库来模拟旧版/导入异常数据，
      // 确保过滤规则不只处理普通空格，也覆盖换行、制表符和全角空格。
      final blankDates = ['2026-11-01', '2026-11-02', '2026-11-03'];
      final blankContents = ['', '   ', '\n\t\u3000'];
      for (var index = 0; index < blankContents.length; index += 1) {
        await database
            .into(database.dreamRecords)
            .insert(
              DreamRecordsCompanion.insert(
                dreamDate: blankDates[index],
                content: blankContents[index],
                createdAtMillis: 0,
                updatedAtMillis: 0,
              ),
            );
      }
      await repository.save(
        date: DateTime(2026, 11, 4),
        content: '  真正的梦境\n保留换行与首尾空白  ',
      );

      final history = await repository.getAll();

      expect(history, hasLength(1));
      expect(history.single.id, '2026-11-04');
      expect(history.single.content, '  真正的梦境\n保留换行与首尾空白  ');
    });

    test('保存中文、多行及正文两端空白，并保留 UTC 毫秒精度', () async {
      final date = DateTime(2026, 11, 3, 23, 59, 58);
      const content = '  我梦见一座漂浮在云上的图书馆。\n第二层有一片海。  ';

      // 即使时钟返回的是本地时间表示，存储层也应把“瞬间”转换为 UTC。
      currentTime = currentTime.toLocal();
      final saved = await repository.save(date: date, content: content);
      final loaded = await repository.getByDate(DateTime(2026, 11, 3, 8));

      expect(saved.id, '2026-11-03');
      expect(loaded, isNotNull);
      expect(loaded!.id, saved.id);
      expect(loaded.dreamDate, DateTime(2026, 11, 3));
      expect(loaded.content, content);
      expect(loaded.createdAt, DateTime.utc(2026, 11, 3, 1, 2, 3, 456));
      expect(loaded.updatedAt, loaded.createdAt);
      expect(loaded.createdAt.isUtc, isTrue);
      expect(loaded.updatedAt.isUtc, isTrue);
      expect(loaded.createdAt.millisecond, 456);
    });

    test('同一天再次保存是更新，保留 id 和创建时间，不产生第二行', () async {
      final first = await repository.save(
        date: DateTime(2026, 11, 3, 8),
        content: '早晨记下的第一版',
      );

      currentTime = currentTime.add(
        const Duration(minutes: 5, milliseconds: 123),
      );
      final updated = await repository.save(
        date: DateTime(2026, 11, 3, 22, 30),
        content: '晚上补充后的第二版',
      );
      final loaded = await repository.getByDate(DateTime(2026, 11, 3));
      final rows = await database.select(database.dreamRecords).get();

      expect(rows, hasLength(1));
      expect(updated.id, first.id);
      expect(updated.createdAt, first.createdAt);
      expect(updated.updatedAt, currentTime.toUtc());
      expect(updated.updatedAt.isAfter(first.updatedAt), isTrue);
      expect(loaded!.content, '晚上补充后的第二版');
      expect(loaded.createdAt, first.createdAt);
      expect(loaded.updatedAt, updated.updatedAt);
    });

    test('跨午夜及跨年的本地日期分开存储，不因 UTC 转换归到前一天', () async {
      // dreamDate 是“日历上的一天”，与 createdAt/updatedAt 表示的 UTC 瞬间不同。
      // 因而不应该先把梦境日期转成 UTC，再截取日期部分。
      final lastNight = DateTime(2026, 12, 31, 23, 59);
      final newYearMorning = DateTime(2027, 1, 1, 0, 1);

      final first = await repository.save(date: lastNight, content: '旧年的梦');
      final second = await repository.save(
        date: newYearMorning,
        content: '新年的梦',
      );

      expect(first.id, '2026-12-31');
      expect(second.id, '2027-01-01');
      expect(
        (await repository.getByDate(DateTime(2026, 12, 31)))!.content,
        '旧年的梦',
      );
      expect(
        (await repository.getByDate(DateTime(2027, 1, 1, 23)))!.content,
        '新年的梦',
      );
      expect(await database.select(database.dreamRecords).get(), hasLength(2));
    });

    test('按日期删除只影响当天；重复删除不存在的记录也不会报错', () async {
      final today = DateTime(2026, 11, 3);
      final tomorrow = DateTime(2026, 11, 4);
      await repository.save(date: today, content: '将要删除');
      await repository.save(date: tomorrow, content: '需要保留');

      // 删除时传入同一天的任意时刻，都应该命中同一个日期键。
      await repository.deleteByDate(DateTime(2026, 11, 3, 19, 30));
      await repository.deleteByDate(today);

      expect(await repository.getByDate(today), isNull);
      expect((await repository.getByDate(tomorrow))!.content, '需要保留');
      expect(await database.select(database.dreamRecords).get(), hasLength(1));
    });

    test('拒绝纯空白的新记录，也不让纯空白 save 覆盖已有记录', () async {
      final date = DateTime(2026, 11, 3);

      // Repository.save 返回一条有效 DreamEntry，因此不接受“空内容记录”。
      // 页面清空正文时，Controller 应调用 deleteByDate，而不是 save 空字符串。
      for (final blank in ['', '   ', '\n\t  ']) {
        await expectLater(
          repository.save(date: date, content: blank),
          throwsArgumentError,
        );
      }
      expect(await database.select(database.dreamRecords).get(), isEmpty);

      await repository.save(date: date, content: '原来的正文');
      await expectLater(
        repository.save(date: date, content: ' \n '),
        throwsArgumentError,
      );
      expect((await repository.getByDate(date))!.content, '原来的正文');
    });

    test('同一天的并发保存仍然只有一条记录', () async {
      final date = DateTime(2026, 11, 3);

      // Future.wait 同时发出多个请求，可以暴露“先查询后插入”的竞争问题。
      // 不假定并发请求的完成顺序；这里验证的是唯一性及最终值来自某次保存。
      final contents = List.generate(5, (index) => '并发版本 $index');
      await Future.wait([
        for (final content in contents)
          repository.save(date: date, content: content),
      ]);

      expect(await database.select(database.dreamRecords).get(), hasLength(1));
      final loaded = await repository.getByDate(date);
      expect(loaded, isNotNull);
      expect(contents, contains(loaded!.content));
    });
  });

  group('真实 SQLite 文件的持久化', () {
    test('多日期历史在关闭重开后仍保持日期顺序、更新和删除结果', () async {
      await _withTemporaryDatabaseFile((file) async {
        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database);
          await repository.save(date: DateTime(2026, 11, 1), content: '月初第一版');
          await repository.save(date: DateTime(2026, 11, 4), content: '最新一天');
          await repository.save(date: DateTime(2026, 11, 2), content: '稍后删除');
          await repository.save(date: DateTime(2026, 11, 1), content: '月初补充版');
          await repository.deleteByDate(DateTime(2026, 11, 2));
        });

        // 新连接只能从真实文件恢复，不能依赖旧 Repository 或页面缓存。
        await _withFileDatabase(file, (database) async {
          final history = await DriftDreamRepository(database).getAll();

          expect(history.map((entry) => entry.id), [
            '2026-11-04',
            '2026-11-01',
          ]);
          expect(history.map((entry) => entry.content), ['最新一天', '月初补充版']);
        });
      });
    });

    test('关闭数据库后，用全新连接和仓库打开同一文件，正文仍然存在', () async {
      await _withTemporaryDatabaseFile((file) async {
        final date = DateTime(2026, 11, 3);
        final savedAt = DateTime.utc(2026, 11, 3, 12, 34, 56, 789);
        const dream = '离开 App 后，也要留下的梦境。🌙\n还有第二行。';

        // 第一阶段：相当于第一次打开应用、输入正文、等待“已保存”。
        final original = await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database, now: () => savedAt);
          return repository.save(date: date, content: dream);
        });

        // _withFileDatabase 返回前已经关闭了第一份数据库连接。
        // 因而下方不能依赖上一份连接的缓存，更不能依赖内存 Map。
        expect(await file.exists(), isTrue);
        expect(await file.length(), greaterThan(0));

        // 第二阶段：用同一路径建立全新对象，相当于重新启动应用后的读取。
        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database);
          final restored = await repository.getByDate(date);

          expect(restored, isNotNull);
          expect(restored!.id, original.id);
          expect(restored.content, dream);
          expect(restored.createdAt, savedAt);
          expect(restored.updatedAt, savedAt);
          expect(restored.createdAt.isUtc, isTrue);
          expect(restored.dreamDate, date);
        });
      });
    });

    test('更新后重开文件仍然只有一条记录，并保留最初创建时间', () async {
      await _withTemporaryDatabaseFile((file) async {
        final date = DateTime(2026, 11, 3);
        final createdAt = DateTime.utc(2026, 11, 3, 10, 0, 0, 321);
        final updatedAt = DateTime.utc(2026, 11, 3, 11, 0, 0, 654);

        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(
            database,
            now: () => createdAt,
          );
          await repository.save(date: date, content: '第一版');
        });
        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(
            database,
            now: () => updatedAt,
          );
          await repository.save(date: date, content: '修改后的正文');
        });
        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database);
          final restored = await repository.getByDate(date);

          expect(restored!.content, '修改后的正文');
          expect(restored.createdAt, createdAt);
          expect(restored.updatedAt, updatedAt);
          expect(
            await database.select(database.dreamRecords).get(),
            hasLength(1),
          );
        });
      });
    });

    test('删除后再次关闭并重开文件，旧记录不会复活', () async {
      await _withTemporaryDatabaseFile((file) async {
        final date = DateTime(2026, 11, 3);

        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database);
          await repository.save(date: date, content: '稍后清空的记录');
        });
        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database);
          await repository.deleteByDate(date);
        });
        await _withFileDatabase(file, (database) async {
          final repository = DriftDreamRepository(database);

          expect(await repository.getByDate(date), isNull);
          expect(await database.select(database.dreamRecords).get(), isEmpty);
        });
      });
    });
  });
}

/// 为一个测试创建独立的临时目录，并且只清理这个测试自己创建的目录。
///
/// 不使用正式数据库路径，防止运行测试时改动真实梦境记录。
/// finally 即使在断言失败时也会执行，避免不断累积测试产生的 SQLite 文件。
Future<void> _withTemporaryDatabaseFile(
  Future<void> Function(File file) action,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'morpheus_drift_test_',
  );
  final file = File('${directory.path}/dreams.sqlite');
  try {
    await action(file);
  } finally {
    await directory.delete(recursive: true);
  }
}

/// 每次调用都建立并关闭一份连接，让“重开”测试真正跨越数据库实例的生命周期。
///
/// NativeDatabase(file) 直接使用 SQLite 文件，不需要 Android/iOS 的平台插件；
/// 因而这些测试可以在开发机及 GitHub Actions 上运行，无需启动安卓模拟器。
Future<T> _withFileDatabase<T>(
  File file,
  Future<T> Function(AppDatabase database) action,
) async {
  final database = AppDatabase(NativeDatabase(file));
  try {
    return await action(database);
  } finally {
    await database.close();
  }
}
