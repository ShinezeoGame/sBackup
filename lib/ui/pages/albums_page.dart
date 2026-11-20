import 'package:flutter/material.dart';

import '../../core/progress.dart';
import '../../platform/platform.dart';
import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

/// Choix des albums à sauvegarder.
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final t = context.text;
    final albums = controller.albums;
    final selected = controller.selectedAlbumIds;

    return AppPage(
      header: const PageHeader(title: 'Albums'),
      children: [
        if (albums == null)
          EmptyHint(
            icon: Icons.photo_library_outlined,
            title: 'Albums inaccessibles',
            text: 'Autorisez l\'accès aux photos et vidéos pour voir vos albums.',
            action: AppButton(
              label: 'Autoriser',
              kind: ButtonKind.primary,
              onPressed: () => controller.request(PermissionRequest.media),
            ),
          )
        else if (albums.isEmpty)
          const EmptyHint(
            icon: Icons.photo_library_outlined,
            title: 'Aucun album',
            text: 'Aucune photo ni vidéo n\'a été trouvée sur le téléphone.',
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
            child: Text(
              controller.settings.albums == null
                  ? 'Par défaut : appareil photo et captures d\'écran. Cochez ce que vous voulez garder.'
                  : 'Les albums cochés sont sauvegardés. Décocher un album ne supprime rien sur le NAS.',
              style: t.secondary,
            ),
          ),
          for (final album in albums)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: Tile(
                onTap: () => controller.setAlbum(album.id, !selected.contains(album.id)),
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.itemTitle),
                          Text('${plural(album.count, 'élément')} · ${formatBytes(album.bytes)}', style: t.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppSwitch(
                      value: selected.contains(album.id),
                      label: album.name,
                      onChanged: (value) => controller.setAlbum(album.id, value),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
