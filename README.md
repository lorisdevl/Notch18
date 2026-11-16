# Notch18 🔥

Une app macOS qui transforme l'encoche (la caméra) du MacBook en centre de contrôle, façon « Dynamic Island ».
Faite en SwiftUI pour remplacer Boring Notch.

![Icône](Resources/icon_1024.png)

## Ce qu'elle fait

**Encoche fermée** : elle s'élargit pour afficher ce qui est « en direct » (pochette + égaliseur pendant la musique, minuteur, statut de garde, chrono d'intervention) et des petites bulles (changement de morceau, chargeur branché, batterie faible).

**Encoche ouverte** (survol, clic ou ⌥⌘N), 9 onglets :

| Onglet | Contenu |
|---|---|
| 🏠 Accueil | Lecteur Spotify / Musique, agenda du jour (+ bouton visio), météo (Open-Meteo) avec alerte rafales |
| 🗂️ Étagère & AirDrop | Dépose des fichiers sur l'encoche, ressors-les par glisser-déposer, envoi AirDrop |
| 📋 Presse-papiers | Historique du texte copié, recherche, épinglage (mots de passe ignorés) |
| 📝 Notes | Notes rapides avec horodatage |
| 🚀 Mes apps | Lanceur d'applications personnalisable |
| 🌐 Réseau & système | IP/masque, passerelle, DNS, IP publique, Wi-Fi, débit, ping en direct, CPU, RAM, disque, batterie |
| ⏱️ Minuteur | Minuteur, Pomodoro, chrono avec tours |
| 🔥 Mode garde | Statut SPV (dispo, astreinte, garde postée…), horodatage d'intervention, résumé copiable, historique |
| 📷 Miroir | Aperçu caméra |

> Le mode garde est un pense-bête personnel : il ne remplace aucun outil officiel du SDIS.

## Installer

Prérequis : macOS 14 (Sonoma) ou plus récent, et Xcode installé (licence acceptée).

1. Clone le dépôt.
2. Double-clique sur `Installer Notch18.command` (ou lance-le dans le Terminal).

Le script compile avec `swiftc`, signe l'app localement, l'installe dans `/Applications` et la lance.

## Autorisations demandées

Calendrier et Rappels, Automatisation (Spotify / Musique), Caméra (onglet Miroir), Localisation (uniquement pour lire le nom du Wi-Fi, exigé par macOS).

## Structure

```
Sources/      code Swift (AppKit + SwiftUI)
Resources/    Info.plist et icône
Installer Notch18.command   script de compilation / installation
```

Toutes les données restent sur le Mac : `~/Library/Application Support/Notch18/`.
