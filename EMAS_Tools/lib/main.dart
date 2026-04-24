import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'app_theme.dart';
import 'ui/main_shell.dart';
import 'ui/project_hub_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appLinks = AppLinks();
  final Uri? initialLink = await appLinks.getInitialLink();

  final controller = AppController();
  controller.listenAppLinks(appLinks.uriLinkStream);

  runApp(CrashEmasApp(controller: controller));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.handleProtocolUri(initialLink);
  });
}

class CrashEmasApp extends StatelessWidget {
  const CrashEmasApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'EMAS崩溃分析工具',
          theme: AppTheme.light(seedColor: controller.wallpaperThemeSeed),
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.loadingConfig) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '正在加载…',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (controller.bootstrapError != null) {
                final t = Theme.of(context);
                return Scaffold(
                  body: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(Icons.error_outline, size: 40, color: t.colorScheme.error),
                                const SizedBox(height: 16),
                                Text(
                                  '加载配置失败',
                                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  '${controller.bootstrapError}',
                                  style: t.textTheme.bodyMedium?.copyWith(
                                    color: t.colorScheme.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (controller.showProjectHub) {
                return ProjectHubPage(controller: controller);
              }
              return MainShell(controller: controller);
            },
          ),
        );
      },
    );
  }
}
