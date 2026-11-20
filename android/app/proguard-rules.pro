# Règles de R8 pour smbj (partage Windows vers le NAS).

# Classes facultatives que smbj et mbassador référencent sans s'en servir ici :
# authentification Kerberos (GSS-API, absente d'Android) et filtres par expressions.
-dontwarn org.ietf.jgss.**
-dontwarn javax.el.**
-dontwarn org.slf4j.**

# smbj, son bus d'événements (mbassador, par réflexion sur les annotations) et la
# cryptographie de BouncyCastle (signature et chiffrement SMB 3) : rien ne doit être
# retiré ni renommé.
-keep class com.hierynomus.** { *; }
-keep class net.engio.mbassy.** { *; }
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
