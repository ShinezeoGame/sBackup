<p align="center"><img src="docs/logo/sbackup-logo-1024.png" width="148" alt="Logo sBackup : un disque de stockage et un point ambre, sur fond orange"></p>

<h1 align="center">sBackup</h1>

<p align="center"><b>Vos photos et vidéos sauvegardées sur votre NAS, toutes seules, dès que vous rentrez à la maison.</b></p>

<p align="center">
  <a href="https://github.com/ShinezeoGame/sBackup/releases/latest/download/sbackup.apk"><img alt="Télécharger pour Android (APK)" src="https://img.shields.io/badge/T%C3%A9l%C3%A9charger-pour%20Android-F0A257?style=for-the-badge&logo=android&logoColor=white&labelColor=3B2516"></a>
  <a href="https://github.com/ShinezeoGame/sBackup/releases/latest"><img alt="Version" src="https://img.shields.io/github/v/release/ShinezeoGame/sBackup?style=for-the-badge&label=version&color=C2692B&labelColor=3B2516"></a>
</p>

> **Première version.** Tout est en place et testé sur ordinateur, avec un NAS simulé,
> mais sBackup n'a pas encore tourné sur un vrai téléphone face à un vrai NAS. Vos photos
> ne risquent rien (sBackup ne supprime ni ne modifie jamais rien) ; au pire, une
> sauvegarde échoue et l'historique dit pourquoi.

Une alternative à Google Photos qui reste chez vous. Vous rentrez, le téléphone retrouve le
Wi-Fi de la maison, et les photos du jour partent sur votre NAS, rangées par année et par
mois. Pas d'abonnement, pas de nuage, et rien n'est jamais supprimé.

<p align="center">
  <img src="docs/captures/accueil.png" width="250" alt="Accueil : sauvegarde en cours, 12 fichiers sur 340">
  <img src="docs/captures/albums.png" width="250" alt="Choix des albums à sauvegarder">
  <img src="docs/captures/premier-lancement.png" width="250" alt="Thème sombre : premier lancement, les réglages à faire">
</p>

## Pourquoi sBackup

- **Vos souvenirs restent chez vous.** Ils vont du téléphone à votre NAS, sur le réseau de
  la maison, sans passer par Internet ni par le serveur de qui que ce soit.
- **Vous n'y pensez plus.** La sauvegarde se lance toute seule à l'arrivée de nouvelles
  photos et toutes les heures, seulement sur le Wi-Fi de la maison.
- **Rien ne se perd, rien ne s'écrase.** Chaque fichier est vérifié une fois arrivé, aucun
  fichier n'est jamais remplacé, et sBackup ne supprime rien, ni sur le téléphone ni sur le
  NAS.

## Ce que fait sBackup

### 🗄️ Votre NAS Synology, sans rien y installer
sBackup écrit sur le NAS par le partage Windows (SMB), déjà actif sur un Synology. Par
défaut, les photos arrivent dans votre espace personnel, dossier `Photos/Téléphone` :
l'application Synology Photos les affiche d'elle-même. Votre mot de passe reste chiffré
sur le téléphone, et un bouton « Tester » vérifie la connexion tout de suite.

### 🗂️ Les albums de votre choix
L'appareil photo et les captures d'écran sont cochés d'office ; ajoutez ou retirez
n'importe quel album (WhatsApp, Téléchargements…) d'un geste.

### ♻️ Une sauvegarde qui n'envoie que les nouveautés
Un fichier déjà sauvegardé n'est jamais renvoyé, même s'il est dans deux albums. Si le Wi-Fi
saute ou si le téléphone s'éteint en plein envoi, la sauvegarde reprend là où elle s'était
arrêtée, sans recommencer le fichier.

### ✅ Des fichiers vérifiés
Chaque fichier est relu sur le NAS et son empreinte comparée à l'original. Il n'est rangé à
sa place qu'une fois reconnu identique. La position GPS de vos photos est conservée.

### 📶 Seulement à la maison
sBackup reconnaît le Wi-Fi de la maison à son nom. Ailleurs, rien ne part. En option, il
attend aussi que le téléphone soit en charge.

### 📅 Rangé par année et par mois
Sur le NAS, les photos arrivent dans `2026/11/…`, avec leur nom d'origine. Si un fichier du
même nom existe déjà, le nouveau devient `IMG_1234 (2).jpg` : rien n'est écrasé.

### 📊 Vous savez où vous en êtes
Avancement en direct, date de la dernière sauvegarde, historique de chaque passage et
erreurs expliquées en français. Une notification discrète accompagne les gros transferts,
avec un bouton pour arrêter.

### 🔋 Pensé pour Android 15 et Samsung
Les sauvegardes passent par le planificateur d'Android (WorkManager) et deviennent un
service au premier plan pendant les gros transferts. sBackup vous guide pour l'exempter
de l'économie de batterie, sans quoi Samsung l'endormirait.

### 🌗 Clair ou sombre
Un thème clair et un thème sombre, au choix ou selon le téléphone.

## Prise en main

1. **Installez** sBackup sur le téléphone avec le bouton en haut de cette page.
2. **Suivez « À régler »** sur l'accueil : accès aux photos, le NAS (adresse IP, votre
   compte), le Wi-Fi de la maison, l'exemption de batterie.
3. **C'est tout.** Touchez « Sauvegarder maintenant » pour la première fois ; ensuite,
   tout se fait seul.

Le [guide d'utilisation](docs/GUIDE.md) détaille chaque réglage et les solutions aux soucis
courants.

## Questions fréquentes

**Faut-il un compte ou un abonnement ?** Non. sBackup est gratuit, sans compte, sans
publicité.

**Mes photos passent-elles par Internet ?** Non. Elles vont directement du téléphone au
NAS, sur le réseau de la maison.

**sBackup supprime-t-il les photos du téléphone une fois sauvegardées ?** Non, jamais. Il
ne supprime rien, ni sur le téléphone ni sur le NAS. Faire de la place reste votre choix.

**Pourquoi demande-t-il la localisation ?** Parce qu'Android ne donne le nom du Wi-Fi
qu'aux applications autorisées à la localisation. sBackup ne lit ni ne garde aucune
position.

**Et si je retouche une photo ?** La version retouchée est sauvegardée à côté de
l'originale, sous un nom voisin (`IMG_1234 (2).jpg`).

**Avec quel NAS ?** Tout NAS qui propose un partage Windows (SMB 2 ou 3) : Synology, QNAP,
un PC Windows… sBackup a été pensé autour d'un Synology DS415+.

**Avec quels téléphones ?** Android 11 ou plus récent. sBackup a été pensé autour d'un
Samsung Galaxy S25 sous Android 15.

## La famille sPack

sBackup fait partie de **sPack**, une famille d'applications pratiques pour la maison,
toutes dans le même style.

| | | | |
| :---: | :---: | :---: | :---: |
| <a href="https://github.com/ShinezeoGame/sDash"><img src="docs/logo/famille/sdash.png" width="72" alt="Logo sDash"></a> | <a href="https://github.com/ShinezeoGame/sPhone"><img src="docs/logo/famille/sphone.png" width="72" alt="Logo sPhone"></a> | <a href="https://github.com/ShinezeoGame/sDrop"><img src="docs/logo/famille/sdrop.png" width="72" alt="Logo sDrop"></a> | <a href="https://github.com/ShinezeoGame/sPing"><img src="docs/logo/famille/sping.png" width="72" alt="Logo sPing"></a> |
| **[sDash](https://github.com/ShinezeoGame/sDash)**<br>Toute la maison sur une tablette | **[sPhone](https://github.com/ShinezeoGame/sPhone)**<br>L'écran du téléphone sur le PC | **[sDrop](https://github.com/ShinezeoGame/sDrop)**<br>Fichiers et textes entre téléphone et PC | **[sPing](https://github.com/ShinezeoGame/sPing)**<br>Les notifications du téléphone sur le PC |
| <a href="https://github.com/ShinezeoGame/sWatt"><img src="docs/logo/famille/swatt.png" width="72" alt="Logo sWatt"></a> | <a href="https://github.com/ShinezeoGame/sCam"><img src="docs/logo/famille/scam.png" width="72" alt="Logo sCam"></a> | <img src="docs/logo/famille/sbackup.png" width="72" alt="Logo sBackup"> |   |
| **[sWatt](https://github.com/ShinezeoGame/sWatt)**<br>La consommation électrique de la maison<br><sub>bientôt</sub> | **[sCam](https://github.com/ShinezeoGame/sCam)**<br>Un vieux téléphone en caméra ou babyphone<br><sub>bientôt</sub> | **sBackup**<br>Les photos du téléphone sauvegardées sur le NAS<br><sub>bientôt</sub> |   |

---

<sub>Fonctionnement, développement et logo : voir [docs/DEVELOPPEMENT.md](docs/DEVELOPPEMENT.md).
Police [Outfit](https://github.com/Outfitio/Outfit-Fonts) sous licence SIL Open Font License 1.1.</sub>
