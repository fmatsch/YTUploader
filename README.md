# YTUploader

Schlanke, native macOS-App (SwiftUI, keine externen Abhängigkeiten) zum
**Stapel-Upload von YouTube-Videos**.

![App-Icon](icon-1024.png)

## Funktionen

- **Upload-Warteschlange:** Beliebig viele Aufträge anlegen (Video, Thumbnail,
  Titel, Beschreibung, Tags, Kategorie, Sichtbarkeit) — die App lädt sie eines
  nach dem anderen über die offizielle YouTube Data API v3 hoch.
- **Unterbrechungsfest:** Resumable Uploads in 8-MB-Blöcken. Bei Internet-Ausfall
  pausiert die App und setzt automatisch an der letzten bestätigten Stelle fort —
  auch nach einem Neustart der App.
- **Geplante Veröffentlichung:** Termin wählen, YouTube schaltet das Video zum
  Zeitpunkt automatisch öffentlich. Ein Monatskalender markiert Tage, an denen
  bereits Videos geplant sind.
- **KI-Texthilfe (optional):** Titel und Beschreibung per OpenAI-API verbessern
  oder verlängern, passende Tags vorschlagen lassen.
- **Sicher:** OAuth-Anmeldung bei Google (PKCE, Loopback), Tokens und API-Keys
  liegen im macOS-Schlüsselbund.

## Bauen

```bash
./build-app.sh
open YTUploader.app
```

Benötigt macOS 13+ und Xcode bzw. die Swift-Toolchain.

## Einrichtung

Für Uploads ist ein eigenes (kostenloses) Google-Cloud-Projekt mit
OAuth-Client-ID nötig — Schritt-für-Schritt-Anleitung, Bedienung und wichtige
Einschränkungen der YouTube API (Tageskontingent, Audit): siehe
**[ANLEITUNG.md](ANLEITUNG.md)**.
