[← Retour à la présentation](../README.md)

# Guide d'utilisation de sBackup

> **Première version** : pas encore essayée sur un vrai téléphone face à un vrai NAS. Si
> quelque chose coince, l'historique de l'application dit pourquoi.

## Installation

1. Sur le téléphone, téléchargez `sbackup.apk` depuis la
   [dernière version](https://github.com/ShinezeoGame/sBackup/releases/latest).
2. Ouvrez-le. Si Android le demande, autorisez l'installation d'applications de sources
   inconnues pour votre navigateur ou votre gestionnaire de fichiers.
3. Ouvrez sBackup : la section **À régler** de l'accueil liste ce qu'il reste à faire.

## Les réglages à faire une fois

| Réglage | Pourquoi |
| --- | --- |
| **Accès aux photos et vidéos** | Pour lire les fichiers et les envoyer. Choisissez « Tout autoriser » : avec une sélection, les nouvelles photos ne seraient pas vues. La position GPS des photos est conservée dans la copie. |
| **Le NAS** | Son adresse IP, votre identifiant et votre mot de passe du NAS, puis « Enregistrer » : sBackup essaie aussitôt de s'y connecter. Voir ci-dessous. |
| **Le Wi-Fi de la maison** | Les photos ne partent que sur ce réseau. Réglages › Wi-Fi de la maison › « Ajouter » le Wi-Fi actuel, ou tapez son nom. Plusieurs réseaux possibles (box et répéteur). |
| **Localisation « Toujours autoriser »** | Android ne donne le nom du Wi-Fi qu'avec cette autorisation, et seulement si la localisation est activée. sBackup ne lit ni ne garde aucune position. |
| **Économie de batterie** | Touchez « Exempter » et acceptez. Sans cela, Android endort les sauvegardes. |
| **Notifications** | Pour voir l'avancement des gros transferts et pouvoir les arrêter. |

## Le NAS Synology

sBackup écrit sur le NAS par le **partage Windows (SMB)**, actif d'office sur un Synology.

| Champ | Quoi mettre |
| --- | --- |
| **Adresse IP du NAS** | Visible dans DSM (Panneau de configuration › Réseau), dans l'application Synology Assistant ou dans la liste des appareils de votre box. Réservez-lui une adresse fixe dans la box pour qu'elle ne change pas. |
| **Identifiant**, **Mot de passe** | Votre compte DSM, celui avec lequel vous ouvrez l'interface du NAS. Le mot de passe est chiffré sur le téléphone et n'est jamais réaffiché. |
| **Dossier partagé** | `home` (proposé) : votre espace personnel. Ou un autre dossier partagé, `photo` par exemple, si vous préférez. |
| **Dossier des photos** | `Photos/Téléphone` (proposé). Dans `home`, le dossier `Photos` est celui de **Synology Photos** : vos photos y apparaissent d'elles-mêmes. Le dossier est créé s'il n'existe pas. |

Touchez **Enregistrer** : sBackup se connecte et dit tout de suite si c'est bon. Le
bouton **Tester** refait l'essai.

Si la connexion échoue :

- **« Le NAS ne répond pas »** : mauvaise adresse IP, NAS éteint, ou téléphone sur un
  autre réseau.
- **« identifiant ou mot de passe refusé »** : vérifiez-les en vous connectant à DSM.
- **« dossier introuvable… »** avec `home` : le service d'espace personnel est peut-être
  coupé. Dans DSM : Panneau de configuration › Utilisateur et groupe › Avancé › cochez
  « Activer le service d'accueil de l'utilisateur ». Sinon, choisissez un autre dossier
  partagé sur lequel votre compte peut écrire.
- Vérifiez aussi que le service SMB est actif : Panneau de configuration › Services de
  fichiers › SMB.

### Samsung : applications jamais en veille

En plus de l'exemption, Samsung met parfois les applications peu ouvertes en veille. Pour
l'éviter : **Paramètres › Batterie › Limites d'utilisation en arrière-plan › Applications
jamais en veille › +** et ajoutez sBackup.

## Quand la sauvegarde a-t-elle lieu ?

Avec la **sauvegarde automatique** (activée par défaut) :

- une minute environ après l'arrivée de nouvelles photos ou vidéos ;
- et toutes les heures environ, pour rattraper ce qui aurait été manqué.

À chaque fois, sBackup vérifie que le téléphone est sur le Wi-Fi de la maison et, si vous
l'avez demandé, qu'il est en charge. Sinon, il attend. Android décide de l'heure exacte :
elle peut varier de quelques minutes.

« **Sauvegarder maintenant** » lance un passage tout de suite (toujours seulement sur le
Wi-Fi de la maison).

## Ce qui arrive sur le NAS

```
home/Photos/Téléphone/
├── 2025/
│   └── 12/
│       ├── IMG_20251224_193012.jpg
│       └── VID_20251225_101500.mp4
└── 2026/
    └── 11/
        ├── IMG_20261119_184502.jpg
        └── IMG_20261119_184502 (2).jpg   ← un autre fichier du même nom
```

- Rangement par **année et mois de la prise de vue**, nom d'origine conservé.
- Un fichier existant n'est **jamais remplacé** : le nouveau prend le nom suivant, `(2)`,
  `(3)`…
- Un dossier caché `.sbackup-partiel` contient les envois en cours. Un fichier n'en sort,
  renommé à sa place, qu'une fois arrivé en entier et vérifié. Ne le supprimez pas pendant
  une sauvegarde ; entre deux sauvegardes, il est vide ou ne contient que des envois à
  reprendre.

## Ce que sBackup ne fait pas

- Il ne **supprime rien**, ni sur le téléphone, ni sur le NAS.
- Il ne **modifie pas** vos photos.
- Il n'envoie rien **hors du Wi-Fi de la maison**, ni vers Internet.

## Soucis courants

**« Le nom du Wi-Fi n'est pas lisible »** : la localisation est désactivée, ou sBackup n'a
pas l'autorisation « Toujours autoriser ». Réglez-la depuis la section À régler.

**« Ce Wi-Fi n'est pas celui de la maison »** : le nom enregistré ne correspond pas
exactement (majuscules, espaces). Ajoutez le Wi-Fi actuel depuis les réglages, avec le
bouton « Ajouter « … » ».

**« Le NAS ne répond pas »** : vérifiez qu'il est allumé et que son adresse n'a pas changé
(réservez-lui une adresse fixe dans votre box).

**Les sauvegardes automatiques n'ont plus lieu** : vérifiez l'exemption de batterie et,
sur Samsung, les « Applications jamais en veille ».

**Un fichier est en échec dans l'historique** : l'explication est donnée à côté du nom. Un
fichier en échec est réessayé au passage suivant.
