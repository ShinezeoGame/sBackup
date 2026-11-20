import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../platform/platform.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

/// Réglages : le NAS, le Wi-Fi de la maison, les conditions, l'apparence.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppController _controller = AppScope.read(context);
  late final _host = TextEditingController(text: _controller.settings.destination.host);
  late final _share = TextEditingController(text: _controller.settings.destination.share);
  late final _folder = TextEditingController(text: _controller.settings.destination.folder);
  late final _user = TextEditingController(text: _controller.settings.destination.user);
  final _password = TextEditingController();
  final _network = TextEditingController();

  @override
  void dispose() {
    for (final c in [_host, _share, _folder, _user, _password, _network]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _destinationChanged {
    final d = _controller.settings.destination;
    return _host.text.trim() != d.host ||
        _share.text.trim() != d.share ||
        _folder.text.trim() != d.folder ||
        _user.text.trim() != d.user ||
        _password.text.isNotEmpty;
  }

  Future<void> _saveDestination() async {
    await _controller.saveDestination(
      DestinationConfig(
        host: _host.text.trim(),
        share: _share.text.trim(),
        folder: _folder.text.trim(),
        user: _user.text.trim(),
      ),
      password: _password.text,
    );
    _password.clear();
    if (mounted) setState(() {});
  }

  Future<void> _addNetwork(String name) async {
    await _controller.addHomeNetwork(name);
    _network.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = controller.settings;
    final t = context.text;
    final current = controller.device?.ssid;

    return AppPage(
      header: const PageHeader(title: 'Réglages'),
      children: [
        const SectionTitle('Le NAS', detail: 'partage Windows (SMB)'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _host,
                decoration: const InputDecoration(labelText: 'Adresse IP du NAS', hintText: '192.168.1.10'),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'Identifiant', helperText: 'Votre compte du NAS (DSM).'),
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  helperText: controller.hasPassword
                      ? 'Enregistré et chiffré sur le téléphone. Laissez vide pour le garder.'
                      : 'Gardé chiffré sur le téléphone, jamais affiché.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _share,
                decoration: const InputDecoration(
                  labelText: 'Dossier partagé',
                  helperText: '« home » : votre espace personnel du Synology.',
                ),
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _folder,
                decoration: const InputDecoration(
                  labelText: 'Dossier des photos',
                  helperText: 'Dans « home », le dossier Photos est affiché par Synology Photos. Créé s\'il manque.',
                ),
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              if (controller.destinationTest case final result?) ...[
                const SizedBox(height: 12),
                MessageBanner(message: result.message, error: result.error),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: 'Tester',
                    busy: controller.testingDestination,
                    onPressed: _destinationChanged ? null : controller.testDestination,
                  ),
                  AppButton(
                    label: 'Enregistrer',
                    kind: ButtonKind.primary,
                    busy: controller.testingDestination,
                    onPressed: _destinationChanged ? _saveDestination : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle('Wi-Fi de la maison', detail: s.homeNetworks.isEmpty ? null : 'seuls réseaux utilisés'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.homeNetworks.isEmpty)
                Text('Aucun : la sauvegarde attend que vous en indiquiez un.', style: t.secondary)
              else
                for (final ssid in s.homeNetworks)
                  Row(
                    children: [
                      Icon(Icons.wifi_rounded, size: 20, color: context.colors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(ssid, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                      ),
                      SquareButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Retirer $ssid',
                        size: 44,
                        onPressed: () => controller.removeHomeNetwork(ssid),
                      ),
                    ],
                  ),
              if (current != null && !s.homeNetworks.contains(current)) ...[
                const SizedBox(height: 10),
                AppButton(
                  label: 'Ajouter « $current »',
                  icon: Icons.add_rounded,
                  expand: true,
                  onPressed: () => _addNetwork(current),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _network,
                      decoration: const InputDecoration(labelText: 'Nom du Wi-Fi'),
                      autocorrect: false,
                      onSubmitted: _addNetwork,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppButton(label: 'Ajouter', onPressed: () => _addNetwork(_network.text)),
                ],
              ),
              if (!controller.permissions.backgroundLocation) ...[
                const SizedBox(height: 8),
                Text(
                  'Android ne donne le nom du Wi-Fi qu\'avec la localisation « Toujours autoriser ». '
                  'sBackup ne lit ni ne garde aucune position.',
                  style: t.caption,
                ),
              ],
            ],
          ),
        ),
        const SectionTitle('Quand sauvegarder'),
        Tile(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              SettingRow(
                title: 'Sauvegarde automatique',
                subtitle: 'Toutes les heures et à chaque nouvelle photo, sur le Wi-Fi de la maison.',
                trailing: AppSwitch(
                  value: s.autoBackup,
                  label: 'Sauvegarde automatique',
                  onChanged: (v) => controller.updateSettings(s.copyWith(autoBackup: v)),
                ),
              ),
              SettingRow(
                title: 'Seulement en charge',
                subtitle: 'Attendre que le téléphone soit branché.',
                trailing: AppSwitch(
                  value: s.requireCharging,
                  label: 'Seulement en charge',
                  onChanged: (v) => controller.updateSettings(s.copyWith(requireCharging: v)),
                ),
              ),
              SettingRow(
                title: 'Vérification complète',
                subtitle: 'Relire chaque fichier sur le NAS et comparer son empreinte. Sinon, la taille seule.',
                trailing: AppSwitch(
                  value: s.deepVerify,
                  label: 'Vérification complète',
                  onChanged: (v) => controller.updateSettings(s.copyWith(deepVerify: v)),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Arrière-plan'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingRow(
                title: 'Économie de batterie',
                subtitle: controller.permissions.batteryUnrestricted
                    ? 'sBackup en est exempté : les sauvegardes ont lieu.'
                    : 'Sans exemption, Android peut endormir les sauvegardes.',
                trailing: controller.permissions.batteryUnrestricted
                    ? Icon(Icons.check_circle_rounded, color: context.colors.success)
                    : AppButton(
                        label: 'Exempter',
                        compact: true,
                        onPressed: () => controller.request(PermissionRequest.battery),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sur Samsung, ajoutez aussi sBackup aux « Applications jamais en veille » : Paramètres › '
                'Batterie › Limites d\'utilisation en arrière-plan.',
                style: t.caption,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Autorisations de l\'appli',
                icon: Icons.open_in_new_rounded,
                expand: true,
                onPressed: () => controller.request(PermissionRequest.appSettings),
              ),
            ],
          ),
        ),
        const SectionTitle('Apparence'),
        Segmented<AppThemeMode>(
          values: AppThemeMode.values,
          selected: s.theme,
          labelOf: (m) => switch (m) {
            AppThemeMode.auto => 'Automatique',
            AppThemeMode.light => 'Clair',
            AppThemeMode.dark => 'Sombre',
          },
          onSelected: (m) => controller.updateSettings(s.copyWith(theme: m)),
        ),
        const SizedBox(height: 18),
        Text(
          'sBackup ne supprime jamais rien, ni sur le téléphone ni sur le NAS.',
          textAlign: TextAlign.center,
          style: t.caption,
        ),
      ],
    );
  }
}
