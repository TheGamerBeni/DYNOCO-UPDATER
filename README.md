# DynoCo

Programm für Akquise und Marketing-Planung. Hier liegen die fertigen Installer und alles zum
Einrichten – kein Code, keine Daten, keine Schlüssel.

## 👉 Einrichten: https://thegamerbeni.github.io/DYNOCO-UPDATER

Die Seite erkennt Mac oder Windows und zeigt jeden Schritt mit Kopieren-Knopf.
Anleitung als PDF (eine Seite):
https://thegamerbeni.github.io/DYNOCO-UPDATER/einrichtungsguide.pdf

## Kurz erklärt

**Erster Rechner (Mac) – hier kommt die Datenbank hin**

1. Terminal öffnen: ⌘ + Leertaste, „Terminal“ eintippen, Enter.
2. Diese Zeile einfügen und Enter drücken:

   ```
   bash <(curl -fsSL https://thegamerbeni.github.io/DYNOCO-UPDATER/einrichten.sh)
   ```

3. Nach Aufforderung das Mac-Passwort tippen (es erscheinen keine Zeichen).
4. DynoCo öffnet sich: **„Erster Rechner“** → Datenbank einrichten → Inhaber-Konto anlegen →
   Firmenliste einlesen.

**Weitere Rechner**

- **Mac:** dieselbe Zeile mit ` weiterer-rechner` am Ende (installiert kein Docker).
- **Windows:** unter [Releases](https://github.com/TheGamerBeni/DYNOCO-UPDATER/releases/latest)
  die Datei `DynoCo-…-windows-setup.exe` laden und öffnen. Bei der Warnung von Windows auf
  „Weitere Informationen“ → „Trotzdem ausführen“.
- Dann in DynoCo **„Weiterer Rechner“** wählen und den Verbindungscode einfügen (auf dem
  ersten Rechner unter Verwaltung → Datenbank). Den Zugangsschlüssel erstellt ein Inhaber
  unter Verwaltung → Zugangsschlüssel.

**Updates:** DynoCo meldet neue Fassungen selbst. Ein Klick auf **„Jetzt aktualisieren“**
genügt. Was neu ist, steht im Programm und unter
[Releases](https://github.com/TheGamerBeni/DYNOCO-UPDATER/releases).

## Für eure IT: Datenbank auf einem eigenen Server im Internet

Wenn Leute auch von zu Hause oder aus anderen Netzen arbeiten: Die Datenbank läuft dann auf
eurem eigenen oder gemieteten Linux-Server. Die Daten liegen nur dort, nicht in einer
öffentlichen Cloud. Alle Rechner verbinden sich verschlüsselt.

**Was ihr braucht**

- Einen Server mit **Ubuntu 24.04** (mind. 2 Kerne, 4 GB Arbeitsspeicher), z. B. Hetzner Cloud
  „CX22“ in Deutschland (rund 5 € im Monat).
- Eine **Internetadresse** für den Server, z. B. `dynoco.eure-firma.de`: beim Domain-Anbieter
  einen DNS-Eintrag **Typ A** auf die IPv4-Adresse des Servers anlegen.
- Datenschutz: mit dem Server-Anbieter einen **Vertrag zur Auftragsverarbeitung (AVV)**
  abschließen.

**Einrichten**

1. Per SSH als root auf den Server: `ssh root@<IP-Adresse>`
2. Diese Zeile ausführen, am Ende eure Adresse:

   ```
   bash <(curl -fsSL https://thegamerbeni.github.io/DYNOCO-UPDATER/server.sh) dynoco.eure-firma.de
   ```

3. Nach 5–10 Minuten stehen da der **Verbindungscode** (für alle Rechner) und der **erste
   Zugangsschlüssel** (für den Inhaber). Beides steht auch in `/root/dynoco-einrichtung.txt`.
4. Auf jedem Rechner DynoCo installieren, **„Weiterer Rechner“** wählen, Verbindungscode
   einfügen. Am ersten Rechner bei „Anmelden“ → „Ich habe einen Zugangsschlüssel“ den ersten
   Zugangsschlüssel einlösen.

**Was der Server selbst erledigt**

- Verschlüsselung mit automatischem Zertifikat (Let's Encrypt).
- Firewall: nur SSH, 80 und 443 offen. Die Datenbank selbst ist von außen nicht erreichbar.
- Sicherung jede Nacht um 2:30 Uhr nach `/var/backups/dynoco` (14 Tage aufbewahrt).
- Jede Stunde Blick nach einer neuen DynoCo-Fassung: erst sichern, dann aktualisieren; bei
  einem Fehler bleibt die alte Fassung.
- Sicherheits-Updates des Betriebssystems.
- Protokoll: `/var/log/dynoco.log`. Das Skript darf jederzeit noch einmal laufen; die Daten
  bleiben erhalten.

Notfall, wenn niemand mehr Inhaber-Zugang hat (auf dem Server):

```
/opt/dynoco/node/bin/node /opt/dynoco/aktuell/server/dynoco-server.mjs recover --data-dir /var/lib/dynoco
```

## Gut zu wissen

- Der Rechner (bzw. Server) mit der Datenbank muss laufen, solange jemand arbeitet.
- Mac und Windows warnen beim ersten Öffnen, weil DynoCo keine gekaufte Signatur hat. Der Weg
  über die Terminal-Zeile umgeht die Warnung auf dem Mac.
- Fragen zum Programm: in DynoCo links auf **„FAQ“**.
