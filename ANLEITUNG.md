# YTUploader – Anleitung

Schlanke macOS-App zum Stapel-Upload von YouTube-Videos: Aufträge mit Titel,
Beschreibung, Tags, Thumbnail und geplantem Veröffentlichungszeitpunkt anlegen –
die App lädt sie dann eines nach dem anderen hoch. Bricht das Internet ab, wird
der Upload automatisch an der letzten Stelle fortgesetzt (auch nach einem
Neustart der App).

## App bauen und starten

```bash
./build-app.sh
open YTUploader.app
```

Das `YTUploader.app` kann danach auch in den Programme-Ordner gezogen werden.

## Einmalige Einrichtung: Google-API-Zugangsdaten

Die App lädt über die offizielle YouTube Data API hoch. Dafür brauchst du ein
eigenes (kostenloses) Google-Cloud-Projekt – dauert ca. 10 Minuten:

1. <https://console.cloud.google.com> öffnen und mit deinem Google-Konto anmelden.
2. Oben **neues Projekt** anlegen (Name egal, z. B. „YTUploader“).
3. Menü → **APIs & Dienste → Bibliothek** → „YouTube Data API v3“ suchen
   und **aktivieren**.
4. **APIs & Dienste → OAuth-Zustimmungsbildschirm**:
   - Nutzertyp **Extern**, App-Name z. B. „YTUploader“, deine E-Mail eintragen.
   - Unter **Zielgruppe / Testnutzer** deine eigene Gmail-Adresse als Testnutzer
     hinzufügen.
5. **APIs & Dienste → Anmeldedaten → Anmeldedaten erstellen → OAuth-Client-ID**:
   - Anwendungstyp: **Desktop-App**.
   - Die angezeigte **Client-ID** und das **Client-Secret** kopieren.
6. In YTUploader das Zahnrad öffnen, Client-ID und Client-Secret eintragen,
   dann **„Bei YouTube anmelden …“** – der Browser öffnet sich für die
   Google-Anmeldung. (Die Warnung „Google hat diese App nicht überprüft“ ist
   normal, weil es dein privates Projekt ist → „Weiter“.)

Die Tokens landen im macOS-Schlüsselbund; die Anmeldung bleibt dauerhaft
bestehen.

## Wichtige Einschränkungen der YouTube API

- **Tageskontingent:** Standardmäßig erlaubt Google 10 000 „Einheiten“ pro Tag;
  ein Video-Upload kostet 1 600. Das ergibt **ca. 6 Uploads pro Tag** (Reset
  um 9 Uhr MEZ / Mitternacht Pacific Time). Mehr Kontingent kann man bei Google
  kostenlos beantragen („YouTube API Services – Audit and Quota Extension Form“).
- **Sichtbarkeit bei unüberprüften Projekten:** Solange dein API-Projekt nicht
  von YouTube überprüft wurde, werden per API hochgeladene Videos von YouTube
  **auf „privat“ gesperrt** – auch wenn „öffentlich“ oder ein Zeitplan gewählt
  wurde. Die Überprüfung beantragt man über dasselbe Audit-Formular; für
  private Nutzung wird sie in der Regel unkompliziert gewährt. Bis dahin kannst
  du hochgeladene Videos in YouTube Studio manuell öffentlich schalten.
- **Testmodus:** Bleibt der OAuth-Zustimmungsbildschirm im Status „Testing“,
  läuft die Anmeldung nach 7 Tagen ab. Stelle ihn deshalb nach dem ersten
  erfolgreichen Test auf **„In Produktion“** (Veröffentlichen-Knopf) – dann
  bleibt die Anmeldung dauerhaft gültig.
- **Geplante Veröffentlichung:** Das Video wird privat hochgeladen und von
  YouTube zum gewählten Zeitpunkt automatisch öffentlich geschaltet (Feld
  `publishAt`). Benutzerdefinierte Thumbnails erfordern ein für Thumbnails
  freigeschaltetes Konto (Telefonnummer bei YouTube bestätigt).

## Optional: KI-Texthilfe (OpenAI)

Im Auftrags-Editor gibt es neben Titel, Beschreibung und Tags einen ✨-Knopf:
Titel und Beschreibung lassen sich per KI **verbessern** oder **verlängern**,
und passende **Tags werden aus Titel und Beschreibung vorgeschlagen**
(„Rückgängig“ jeweils im selben Menü). Dafür ist ein OpenAI-API-Key nötig:

1. <https://platform.openai.com/api-keys> öffnen und einen API-Key erstellen.
   (Das ist unabhängig von einem ChatGPT-Plus-Abo – die API wird pro Anfrage
   abgerechnet, eine Textverbesserung kostet Bruchteile eines Cents. Ggf. unter
   „Billing“ ein kleines Guthaben, z. B. 5 €, aufladen.)
2. Den Key in YTUploader unter Zahnrad → „KI-Texthilfe (OpenAI)“ eintragen.
   Er wird im macOS-Schlüsselbund gespeichert.

Das verwendete Modell (Standard: `gpt-5-mini`) lässt sich dort ebenfalls ändern.

Hinweis: Einen direkten „Login mit ChatGPT“ bietet OpenAI für eigene Apps nicht
an – der API-Key ist der offizielle Weg.

## Bedienung

- **＋** legt einen neuen Auftrag an (Video, Thumbnail, Titel, Beschreibung,
  Tags, Kategorie, Sichtbarkeit oder Veröffentlichungszeitpunkt).
- Bei „Zeitpunkt planen“ zeigt ein kleiner Kalender mit blauen Punkten, an
  welchen Tagen bereits Videos geplant sind; ein Klick auf einen Tag übernimmt
  das Datum (die Uhrzeit bleibt erhalten).
- **▶ Start** arbeitet die Warteschlange von oben nach unten ab; die
  Reihenfolge lässt sich per Ziehen ändern.
- Bei Internet-Ausfall pausiert die App und setzt automatisch fort, sobald die
  Verbindung wieder da ist – bereits hochgeladene Teile gehen nicht verloren.
- Rechtsklick auf einen Auftrag: Bearbeiten, erneut versuchen, entfernen.
- Die Warteschlange wird unter
  `~/Library/Application Support/YTUploader/queue.json` gespeichert und
  übersteht App-Neustarts.
