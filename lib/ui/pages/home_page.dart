import 'package:flutter/material.dart';

import '../../core/conditions.dart';
import '../../core/history.dart';
import '../../core/progress.dart';
import '../../platform/platform.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'albums_page.dart';
import 'history_page.dart';
import 'page_scaffold.dart';
import 'settings_page.dart';

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// Page d'accueil : état de la sauvegarde, réglages qui manquent, résumé, historique.
class HomePage extends StatelessWidget {
  const HomePage({super.key, this.now});

  /// Heure de référence des dates affichées (tests et captures).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final t = context.text;
    final todo = setupSteps(controller);
    final albums = controller.albums;
    final selected = controller.selectedAlbumIds;
    final clock = (now ?? DateTime.now)();

    return AppPage(
      header: const _HomeHeader(),
      children: [
        const NoticeArea(),
        _StatusTile(now: clock),
        if (todo.isNotEmpty) ...[
          SectionTitle('À régler', detail: todo.length == 1 ? '1 point' : '${todo.length} points'),
          for (final step in todo)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: _SetupTile(step: step),
            ),
        ],
        const SectionTitle('Sur le NAS'),
        Tile(
          child: Row(
            children: [
              const IconBadge(icon: Icons.photo_library_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.savedCount == 0
                          ? 'Rien de sauvegardé pour l\'instant'
                          : plural(controller.savedCount, 'fichier sauvegardé', 'fichiers sauvegardés'),
                      style: t.itemTitle,
                    ),
                    Text(
                      controller.savedCount == 0
                          ? 'Vos photos et vidéos y seront rangées par année et par mois.'
                          : '${formatBytes(controller.savedBytes)}, rangés par année et par mois',
                      style: t.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle(
          'Albums',
          detail: albums == null ? null : '${selected.length} sur ${albums.length}',
          trailing: _LinkButton(label: 'Choisir', onTap: () => _open(context, const AlbumsPage())),
        ),
        Tile(
          onTap: () => _open(context, const AlbumsPage()),
          child: Text(_albumSummary(controller), style: t.secondary),
        ),
        SectionTitle(
          'Historique',
          trailing: controller.history.isEmpty
              ? null
              : _LinkButton(
                  label: 'Tout voir',
                  onTap: () => _open(context, HistoryPage(now: now)),
                ),
        ),
        if (controller.history.isEmpty)
          const EmptyHint(
            icon: Icons.history_rounded,
            title: 'Aucune sauvegarde pour l\'instant',
            text: 'Chaque passage, réussi ou non, sera noté ici avec son explication.',
          )
        else
          for (final run in controller.history.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: RunTile(run: run, now: clock),
            ),
      ],
    );
  }

  static String _albumSummary(AppController controller) {
    final albums = controller.albums;
    if (albums == null) return 'Autorisez l\'accès aux photos et vidéos pour choisir les albums.';
    final names = [
      for (final album in albums)
        if (controller.selectedAlbumIds.contains(album.id)) album.name,
    ];
    if (names.isEmpty) return 'Aucun album choisi : rien ne sera sauvegardé.';
    return names.join(' · ');
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Row(
      children: [
        Image.asset('assets/branding/logo.png', height: 44, filterQuality: FilterQuality.medium),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('sBackup', style: t.pageTitle),
              Text('Vos photos, chez vous', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
            ],
          ),
        ),
        SquareButton(
          icon: Icons.tune_rounded,
          tooltip: 'Réglages',
          size: 44,
          onPressed: () => _open(context, const SettingsPage()),
        ),
      ],
    );
  }
}

/// Lien d'action à droite d'un titre de section (« Tout voir »), zone cliquable de 44 px.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: context.text.button.copyWith(color: context.colors.accent)),
            ),
          ),
        ),
      ),
    );
  }
}

/// La tuile principale : sauvegarde en cours, ou état et dernière sauvegarde.
class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final c = context.colors;
    final t = context.text;
    final p = controller.progress;

    if (p.running) {
      final detail = switch (p.phase) {
        BackupPhase.preparing => 'Préparation : liste des photos et connexion au NAS…',
        BackupPhase.finishing => 'Fin de la sauvegarde…',
        _ => p.currentFile.isEmpty ? 'Envoi…' : p.currentFile,
      };
      return Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.cloud_upload_outlined, tone: BadgeTone.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sauvegarde en cours', style: t.itemTitle),
                      Text(
                        p.filesTotal > 0 ? '${p.filesDone} sur ${plural(p.filesTotal, 'fichier')}' : 'Un instant…',
                        style: t.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ProgressBar(value: p.phase == BackupPhase.sending ? p.fraction : null),
            const SizedBox(height: 8),
            Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
            if (p.bytesTotal > 0)
              Text('${formatBytes(p.bytesDone)} sur ${formatBytes(p.bytesTotal)}', style: t.caption),
            const SizedBox(height: 12),
            AppButton(label: 'Arrêter', icon: Icons.stop_rounded, expand: true, onPressed: controller.stop),
          ],
        ),
      );
    }

    final blocker = controller.blocker;
    final last = controller.lastBackup;
    final ok = blocker == null;
    final (title, icon) = switch (blocker) {
      null => ('Prêt à sauvegarder', Icons.check_rounded),
      Blocker.noDestination || Blocker.noHomeNetwork => ('À configurer', Icons.settings_outlined),
      _ => ('En attente', Icons.schedule_rounded),
    };
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, tone: ok ? BadgeTone.accent : BadgeTone.neutral),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.itemTitle),
                    Text(
                      blocker != null
                          ? describeBlocker(blocker)
                          : controller.settings.autoBackup
                          ? 'Les nouvelles photos partent toutes seules, sur le Wi-Fi de la maison.'
                          : 'Sauvegarde automatique coupée : lancez-la vous-même.',
                      style: t.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: c.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  last == null ? 'Jamais sauvegardé' : 'Dernière sauvegarde ${formatWhen(last.end, now)}',
                  style: t.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Sauvegarder maintenant',
            icon: Icons.backup_outlined,
            kind: ButtonKind.primary,
            expand: true,
            onPressed: controller.runNow,
          ),
        ],
      ),
    );
  }
}

/// Un réglage qui manque pour que la sauvegarde fonctionne bien.
class SetupStep {
  const SetupStep({required this.icon, required this.title, required this.text, required this.action, this.onTap});

  final IconData icon;
  final String title;
  final String text;
  final String action;

  /// Action ; `null` pour ouvrir une page de l'application (voir [page]).
  final Future<void> Function()? onTap;

  Widget? get page => null;
}

class _PageStep extends SetupStep {
  const _PageStep({
    required super.icon,
    required super.title,
    required super.text,
    required super.action,
    required this.target,
  });

  final Widget target;

  @override
  Widget? get page => target;
}

/// Ce qui reste à régler, du plus important au moins important.
List<SetupStep> setupSteps(AppController controller) {
  final p = controller.permissions;
  final s = controller.settings;
  return [
    if (p.media == MediaAccess.none)
      SetupStep(
        icon: Icons.photo_outlined,
        title: 'Accès aux photos et vidéos',
        text: 'Pour les lire et les envoyer au NAS, sans jamais les modifier.',
        action: 'Autoriser',
        onTap: () => controller.request(PermissionRequest.media),
      )
    else if (p.media == MediaAccess.partial)
      SetupStep(
        icon: Icons.photo_outlined,
        title: 'Accès à toutes les photos',
        text: 'Seule une sélection est autorisée : les nouvelles photos ne seraient pas sauvegardées.',
        action: 'Tout autoriser',
        onTap: () => controller.request(PermissionRequest.appSettings),
      ),
    if (!s.destination.isComplete)
      const _PageStep(
        icon: Icons.dns_outlined,
        title: 'Le NAS',
        text: 'Son adresse sur le réseau de la maison et le dossier où ranger les photos.',
        action: 'Indiquer',
        target: SettingsPage(),
      ),
    if (s.homeNetworks.isEmpty)
      const _PageStep(
        icon: Icons.wifi_rounded,
        title: 'Le Wi-Fi de la maison',
        text: 'Les photos ne partent que sur ce réseau.',
        action: 'Indiquer',
        target: SettingsPage(),
      ),
    if (!p.location)
      SetupStep(
        icon: Icons.wifi_find_rounded,
        title: 'Reconnaître le Wi-Fi',
        text: 'Android ne donne le nom du Wi-Fi qu\'avec la localisation. sBackup ne garde aucune position.',
        action: 'Autoriser',
        onTap: () => controller.request(PermissionRequest.location),
      )
    else if (!p.backgroundLocation)
      SetupStep(
        icon: Icons.wifi_find_rounded,
        title: 'Reconnaître le Wi-Fi appli fermée',
        text: 'Choisissez « Toujours autoriser » : sinon, la sauvegarde automatique attend.',
        action: 'Régler',
        onTap: () => controller.request(PermissionRequest.backgroundLocation),
      ),
    if (p.location && !p.locationEnabled)
      SetupStep(
        icon: Icons.location_off_outlined,
        title: 'Localisation désactivée',
        text: 'Sans elle, Android cache le nom du Wi-Fi.',
        action: 'Activer',
        onTap: () => controller.request(PermissionRequest.locationSettings),
      ),
    if (!p.batteryUnrestricted)
      SetupStep(
        icon: Icons.battery_saver_outlined,
        title: 'Économie de batterie',
        text: 'Sans exemption, Samsung endort sBackup et les sauvegardes n\'ont plus lieu.',
        action: 'Exempter',
        onTap: () => controller.request(PermissionRequest.battery),
      ),
    if (!p.notifications)
      SetupStep(
        icon: Icons.notifications_none_rounded,
        title: 'Notification des gros transferts',
        text: 'Une notification discrète montre l\'avancement et permet d\'arrêter.',
        action: 'Autoriser',
        onTap: () => controller.request(PermissionRequest.notifications),
      ),
  ];
}

class _SetupTile extends StatelessWidget {
  const _SetupTile({required this.step});

  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final c = context.colors;
    return Tile(
      key: ValueKey('etape ${step.title}'),
      active: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: step.icon, tone: BadgeTone.onActive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title, style: t.itemTitle.copyWith(color: c.onActive)),
                    Text(step.text, style: t.secondary.copyWith(color: c.onActive)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: step.action,
              kind: ButtonKind.primary,
              onActive: true,
              compact: true,
              onPressed: () {
                final page = step.page;
                if (page != null) {
                  _open(context, page);
                } else {
                  step.onTap?.call();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Un passage de sauvegarde dans l'historique.
class RunTile extends StatelessWidget {
  const RunTile({super.key, required this.run, required this.now, this.showErrors = false});

  final RunRecord run;
  final DateTime now;

  /// Détaille les fichiers en échec (page Historique).
  final bool showErrors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (label, color) = switch (run.outcome) {
      RunOutcome.success => ('Réussie', c.success),
      RunOutcome.partial => ('Incomplète', c.danger),
      RunOutcome.interrupted => ('Interrompue', c.textMuted),
      RunOutcome.failed => ('Échec', c.danger),
      RunOutcome.skipped => ('En attente', c.textFaint),
    };
    final trigger = switch (run.trigger) {
      RunTrigger.manual => 'à la demande',
      RunTrigger.scheduled => 'automatique',
      RunTrigger.newMedia => 'nouvelles photos',
    };
    final errors = showErrors ? run.errors : const <String>[];
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: color),
              const SizedBox(width: 8),
              Text(label, style: t.itemTitle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${formatWhen(run.end, now)} · $trigger',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: t.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(run.message, style: t.secondary),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final error in errors.take(10))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $error', style: t.caption),
              ),
            if (errors.length > 10) Text('… et ${errors.length - 10} autres', style: t.caption),
          ],
        ],
      ),
    );
  }
}
