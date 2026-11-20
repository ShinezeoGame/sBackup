import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/tiles.dart';
import 'home_page.dart';
import 'page_scaffold.dart';

/// Tous les passages de sauvegarde, avec le détail des fichiers en échec.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.now});

  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final clock = (now ?? DateTime.now)();
    return AppPage(
      header: const PageHeader(title: 'Historique'),
      children: [
        if (controller.history.isEmpty)
          const EmptyHint(
            icon: Icons.history_rounded,
            title: 'Aucune sauvegarde pour l\'instant',
            text: 'Chaque passage sera noté ici avec son explication.',
          )
        else
          for (final run in controller.history)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: RunTile(run: run, now: clock, showErrors: true),
            ),
      ],
    );
  }
}
