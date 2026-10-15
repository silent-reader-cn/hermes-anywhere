import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowTitleService 纯函数 formatWindowTitle 单元测试', () {
    test('null / 空串 / 纯空格 返回默认 Hermes Anywhere', () {
      expect(WindowTitleService.formatWindowTitle(null), 'Hermes Anywhere');
      expect(WindowTitleService.formatWindowTitle(''), 'Hermes Anywhere');
      expect(WindowTitleService.formatWindowTitle('   '), 'Hermes Anywhere');
    });

    test('占位标题 untitled / untitled session 大小写均返回 Hermes Anywhere', () {
      expect(WindowTitleService.formatWindowTitle('Untitled'), 'Hermes Anywhere');
      expect(WindowTitleService.formatWindowTitle('untitled'), 'Hermes Anywhere');
      expect(
        WindowTitleService.formatWindowTitle('Untitled Session'),
        'Hermes Anywhere',
      );
      expect(
        WindowTitleService.formatWindowTitle('untitled session'),
        'Hermes Anywhere',
      );
      expect(WindowTitleService.formatWindowTitle('  UNTITLED  '), 'Hermes Anywhere');
    });

    test('正常会话标题格式化为 "标题 - Hermes Anywhere"', () {
      expect(
        WindowTitleService.formatWindowTitle('Flutter 桌面端开发'),
        'Flutter 桌面端开发 - Hermes Anywhere',
      );
      expect(
        WindowTitleService.formatWindowTitle('  重构架构讨论  '),
        '重构架构讨论 - Hermes Anywhere',
      );
      expect(
        WindowTitleService.formatWindowTitle('🚀 Release 1.0'),
        '🚀 Release 1.0 - Hermes Anywhere',
      );
    });

    test('长标题超过 40 字符截断并追加省略号', () {
      const exact40 = '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十';
      expect(exact40.length, 40);
      expect(
        WindowTitleService.formatWindowTitle(exact40),
        '$exact40 - Hermes Anywhere',
      );

      const longTitle = '这是一个非常非常非常非常非常非常非常非常非常长的一个会话标题用于测试窗口标题截断功能是否正确生效';
      final formatted = WindowTitleService.formatWindowTitle(longTitle);
      expect(formatted.endsWith('... - Hermes Anywhere'), isTrue);
      // 截断后的主体长度应为 40 字符 + 3 个点
      final prefix = formatted.split(' - Hermes Anywhere').first;
      expect(prefix.length, 43);
      expect(prefix.endsWith('...'), isTrue);
    });

    test('支持自定义 maxLength 截断', () {
      expect(
        WindowTitleService.formatWindowTitle('1234567890', maxTitleLength: 5),
        '12345... - Hermes Anywhere',
      );
    });
  });

  group('WindowTitleService 服务行为测试', () {
    test('非桌面平台 setTitle / updateSessionTitle / resetTitle 安全 no-op', () async {
      String? calledTitle;
      final service = WindowTitleService(
        isDesktop: false,
        onSetTitle: (t) => calledTitle = t,
      );

      await service.setTitle('Custom Title');
      expect(service.currentTitle, 'Custom Title');
      expect(calledTitle, isNull);

      await service.updateSessionTitle('My Session');
      expect(service.currentTitle, 'My Session - Hermes Anywhere');
      expect(calledTitle, isNull);

      await service.resetTitle();
      expect(service.currentTitle, 'Hermes Anywhere');
      expect(calledTitle, isNull);
    });

    test(
      '桌面平台 setTitle / updateSessionTitle / resetTitle 触发 onSetTitle',
      () async {
        String? calledTitle;
        final service = WindowTitleService(
          isDesktop: true,
          onSetTitle: (t) => calledTitle = t,
        );

        await service.setTitle('Hermes Anywhere Client');
        expect(calledTitle, 'Hermes Anywhere Client');

        await service.updateSessionTitle('调试网络模块');
        expect(calledTitle, '调试网络模块 - Hermes Anywhere');

        await service.updateSessionTitle('Untitled');
        expect(calledTitle, 'Hermes Anywhere');

        await service.resetTitle();
        expect(calledTitle, 'Hermes Anywhere');
      },
    );

    test('Provider 注入与 activeSessionIdProvider 状态管理', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(windowTitleServiceProvider);
      expect(service, isNotNull);

      expect(container.read(activeSessionIdProvider), isNull);
      container.read(activeSessionIdProvider.notifier).state = 'session-123';
      expect(container.read(activeSessionIdProvider), 'session-123');
    });
  });
}
