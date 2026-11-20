# sBackup — notes pour Claude

- **Toujours communiquer avec l'utilisateur en français.** L'interface, les commentaires
  et les messages de commit sont aussi en français.
- Application Flutter pour **Android** (Samsung Galaxy S25, Android 15) : sauvegarde
  automatique des photos et vidéos du téléphone sur le NAS de l'utilisateur, seulement sur
  le Wi-Fi de la maison. Pas de version Windows pour l'instant.
- Architecture (détails dans `docs/DEVELOPPEMENT.md`) :
  - `lib/core/` : Dart pur, testé sans téléphone ni NAS. `destination.dart` (interface
    `Destination` + destinations en mémoire et dossier local), `engine.dart` (envoi, reprise,
    vérification, rangement `AAAA/MM`), `backup_index.dart` (journal JSON Lines),
    `backup_job.dart` (un passage complet, `SystemPort`), `conditions.dart`, `history.dart`,
    `settings.dart`.
  - `lib/platform/` : `PhonePlatform` et sa version Android (canal `sbackup/systeme`,
    événements `sbackup/progression`) ; `destinations.dart` crée la destination réelle.
  - `lib/background.dart` : sauvegarde en arrière-plan, appelée par `BackupWorker.kt` via
    `sauvegardeArrierePlan` (doit rester dans `lib/main.dart`).
  - `lib/state/app_controller.dart` : état de l'interface.
  - Android : `BackupScheduler.kt` (WorkManager : horaire, nouvelle photo, immédiat),
    `BackupWorker.kt` (moteur Flutter sans interface, service au premier plan `dataSync`),
    `SystemChannel.kt`, `MediaQueries.kt`, `ProgressHub.kt`, `StopReceiver.kt`,
    `SmbChannel.kt`, `SecretStore.kt`.
- **Le NAS de l'utilisateur** : Synology DS415+. Protocole : partage Windows (SMB 2/3),
  `SmbDestination` (Dart) ↔ canal `sbackup/smb` ↔ `SmbChannel.kt` (smbj). Par défaut :
  partage `home`, dossier `Photos/Téléphone` (visible dans Synology Photos). Mot de passe
  chiffré par `SecretStore.kt` (AndroidKeyStore), jamais renvoyé au Dart. Albums par
  défaut : appareil photo et captures d'écran, **pas WhatsApp** (demande de l'utilisateur).
- Règles à ne pas affaiblir : **jamais de suppression** sur le téléphone ni sur le NAS
  (la seule écriture qui repart de zéro concerne les `.part` de `.sbackup-partiel`) ;
  jamais d'écrasement (`renameNoReplace`, `candidateNames`) ; un fichier n'est rangé
  qu'après vérification ; l'index n'est écrit qu'après le rangement ; rien n'est envoyé
  hors des Wi-Fi de la maison.
- Direction artistique : celle de **sDash**, **sPhone** et **sDrop**. Interface à plat (ni
  texture, ni flou, ni dégradé décoratif), tons chauds, thème clair et sombre, police Outfit.
  - Couleurs uniquement par rôle : `context.colors` / `context.text` (`lib/ui/theme.dart`),
    jamais de couleur en dur dans un widget. Zones cliquables d'au moins 44 px.
  - Tuile ambrée = réglage à faire (« À régler ») ; ses boutons utilisent
    `AppButton(onActive: true)`.
  - Composants dans `lib/ui/widgets/` ; chaque page passe par `AppPage` (`page_scaffold.dart`).
  - Tout doit tenir sans débordement sur un téléphone (testé à 320 × 568, 360 × 780 et
    texte agrandi à 130 %).
- Vérifications avant de pousser : `dart format -l 120 lib test`, `flutter analyze`,
  `flutter test` (`test/core_test.dart` : moteur et passages contre une destination
  factice ; `test/smb_test.dart` : la destination SMB contre un faux NAS derrière le canal ;
  `test/app_test.dart` : l'interface à trois tailles).
- Captures de la documentation : `SBACKUP_CAPTURES=1 flutter test test/captures_test.dart`.
- La CI (`.github/workflows/build.yml`) vérifie le format, analyse, teste et compile l'APK
  (`sbackup-android`). La Release n'est publiée que sur `main` ou à la demande. Travailler
  sur une branche `claude/…`, pas sur `main`.
- Jamais essayé sur un vrai téléphone ni avec un vrai NAS au moment de l'écriture : la
  partie Android n'est vérifiée que par la compilation (pas de SDK Android dans le
  conteneur), le moteur que par des destinations factices.
- Logo : marque « s » de la famille sPack. Même carré arrondi orange `#C2571A`, même trait
  clair à bouts ronds, dessin **centré**, **point ambre posé ensuite dans l'angle en haut à
  droite**, toujours au même endroit et de la même taille (ne jamais décaler le dessin).
  Le dessin de sBackup est **un disque** (pile de stockage, celle du NAS), choisi par
  l'utilisateur : ne pas retoucher le tracé.
  Source : `tools/logo/generer_logo.py`, **identique dans tous les dépôts de sPack, seule
  `APPLI_DU_DEPOT` diffère ; le recopier dans les autres après chaque modification** →
  `docs/logo/*.svg`, puis `tools/logo/exporter.py` → PNG et icônes Android. Fond de
  l'icône adaptative : couleur `sbackup_icon_background` (`values/colors.xml`). L'icône de
  notification (`res/drawable/ic_notification.xml`) reprend le tracé `DISQUE`.
  Icônes de la famille (README) : `docs/logo/famille/`.
