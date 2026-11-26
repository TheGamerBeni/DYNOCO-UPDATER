#!/bin/bash
# DynoCo auf einem Mac einrichten: Docker Desktop installieren und starten,
# DynoCo installieren und öffnen. Lädt immer die neueste veröffentlichte Fassung von
# GitHub. Nur wenn das nicht geht, nimmt es eine DynoCo-Datei aus dem Ordner "Downloads".
# Starten (so steht es auf der Download-Seite), im Terminal:
#   bash <(curl -fsSL https://thegamerbeni.github.io/DYNOCO-UPDATER/einrichten.sh)
# Bestehende Daten bleiben: Das Skript ersetzt nur das Programm, nie die Datenbank.
set -u

# „weiterer-rechner“: Auf diesem Mac kommt keine Datenbank hin – Docker wird nicht gebraucht.
MODE="${1:-}"

say_step() { printf '\n== %s ==\n' "$1"; }
stop() { printf '\nABBRUCH: %s\n' "$1"; read -r -p "Eingabetaste zum Schließen …" _; exit 1; }

case "$(uname -m)" in
  arm64) DOCKER_ARCH=arm64; APP_ARCH=arm64 ;;
  x86_64) DOCKER_ARCH=amd64; APP_ARCH=x64 ;;
  *) stop "Unbekannter Mac-Typ: $(uname -m)" ;;
esac

DOCKER_BIN=/Applications/Docker.app/Contents/Resources/bin/docker

# Die zuletzt geänderte DynoCo-Datei im Ordner Downloads (nur als Notlösung ohne Internet).
find_dmg() {
  find "$HOME/Downloads" -maxdepth 3 -name "DynoCo-*-mac-${APP_ARCH}.dmg" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -1
}

# Lädt die neueste veröffentlichte Fassung in den Ordner Downloads und gibt den Pfad aus.
# Gibt nichts aus, wenn es nicht geht. DYNOCO_RELEASE_API setzt nur der Test.
DOWNLOADED=""
download_latest_dmg() {
  local api="${DYNOCO_RELEASE_API:-https://api.github.com/repos/TheGamerBeni/DYNOCO-UPDATER/releases/latest}"
  local info url
  echo "Die neueste Fassung wird von GitHub geladen …"
  info="$(curl -fsSL "$api")" || { echo "GitHub antwortet nicht."; return 1; }
  url="$(printf '%s' "$info" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*mac-'"${APP_ARCH}"'\.dmg"' | grep -o '[a-z]*://[^"]*' | head -1)"
  [ -n "$url" ] || { echo "Auf GitHub ist noch keine Fassung für diesen Mac veröffentlicht."; return 1; }
  curl -fL --progress-bar -o "$HOME/Downloads/$(basename "$url")" "$url" \
    || { echo "DynoCo konnte nicht geladen werden."; return 1; }
  DOWNLOADED="$HOME/Downloads/$(basename "$url")"
}

# Nur für den Test dieses Skripts: nur laden, nichts installieren.
if [ "${DYNOCO_EINRICHTEN_TEST:-}" = "nur-laden" ]; then
  download_latest_dmg || stop "Laden hat nicht geklappt."
  exit 0
fi

if [ "$MODE" = "weiterer-rechner" ]; then
  echo "Weiterer Rechner: Docker wird hier nicht gebraucht, nur DynoCo."
else
say_step "1 von 4: Docker Desktop"
if [ -d /Applications/Docker.app ]; then
  echo "Docker Desktop ist schon installiert."
else
  echo "Docker Desktop wird geladen (rund 600 MB) …"
  TMP_DMG="$(mktemp -d)/Docker.dmg"
  curl -fL --progress-bar -o "$TMP_DMG" "https://desktop.docker.com/mac/main/${DOCKER_ARCH}/Docker.dmg" \
    || stop "Docker Desktop konnte nicht geladen werden. Internet prüfen."
  hdiutil attach "$TMP_DMG" -nobrowse -quiet || stop "Die Docker-Datei ließ sich nicht öffnen."
  echo "Jetzt wird das Passwort eines Mac-Administrators gebraucht."
  echo "Mit der Installation nimmst du die Lizenzbedingungen von Docker an."
  sudo /Volumes/Docker/Docker.app/Contents/MacOS/install --accept-license --user="$USER" \
    || echo "Der Installer von Docker hat einen Fehler gemeldet; ich kopiere das Programm von Hand."
  # Der Installer legt das Programm nicht immer in den Ordner Programme: dann von Hand kopieren.
  if [ ! -d /Applications/Docker.app ]; then
    echo "Docker Desktop wird in den Ordner Programme kopiert …"
    sudo cp -R /Volumes/Docker/Docker.app /Applications/ \
      || { hdiutil detach /Volumes/Docker -quiet; stop "Docker Desktop konnte nicht nach Programme kopiert werden."; }
  fi
  hdiutil detach /Volumes/Docker -quiet
  [ -d /Applications/Docker.app ] || stop "Docker Desktop liegt nach der Installation nicht im Ordner Programme."
fi

say_step "2 von 4: Docker Desktop starten"
open /Applications/Docker.app || stop "Docker Desktop ließ sich nicht starten."
echo "Warte, bis Docker bereit ist (kann beim ersten Mal ein paar Minuten dauern)."
echo "Falls Docker ein Fenster zeigt: Bedingungen annehmen, Anmeldung überspringen."
for i in $(seq 1 120); do
  if "$DOCKER_BIN" info >/dev/null 2>&1; then echo "Docker läuft."; break; fi
  [ "$i" = 120 ] && stop "Docker ist nach 10 Minuten nicht bereit. Docker Desktop öffnen, warten, dann dieses Skript noch einmal starten."
  sleep 5
done
fi

say_step "3 von 4: DynoCo installieren"
# Immer die neueste Fassung laden. Nur ohne Internet eine Datei aus „Downloads“ nehmen.
DMG=""
if download_latest_dmg; then
  DMG="$DOWNLOADED"
else
  DMG="$(find_dmg)"
  [ -n "$DMG" ] && echo "Ohne Internet: Ich nehme die Datei aus Downloads: $(basename "$DMG")"
fi
[ -n "$DMG" ] || stop "DynoCo konnte nicht geladen werden. Internet prüfen und das Skript noch einmal starten."
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MOUNT" || stop "Die DynoCo-Datei ließ sich nicht öffnen."
APP="$(find "$MOUNT" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || { hdiutil detach "$MOUNT" -quiet; stop "In der DynoCo-Datei liegt kein Programm."; }
NAME="$(basename "$APP")"
pkill -x "${NAME%.app}" 2>/dev/null
rm -rf "/Applications/$NAME" 2>/dev/null
cp -R "$APP" /Applications/ 2>/dev/null || sudo cp -R "$APP" /Applications/ \
  || { hdiutil detach "$MOUNT" -quiet; stop "DynoCo konnte nicht nach Programme kopiert werden."; }
hdiutil detach "$MOUNT" -quiet
# Die Sperre für geladene Programme entfernen, sonst meldet der Mac „kann nicht geöffnet werden“.
xattr -dr com.apple.quarantine "/Applications/$NAME" 2>/dev/null || sudo xattr -dr com.apple.quarantine "/Applications/$NAME"
echo "DynoCo liegt jetzt im Ordner Programme."

say_step "4 von 4: DynoCo öffnen"
open "/Applications/$NAME" || stop "DynoCo ließ sich nicht öffnen."
cat <<'EOF'

Fertig. DynoCo ist offen und führt dich durch den Rest:
  Neu hier?   „Erster Rechner“ wählen → Datenbank einrichten → Inhaber-Konto anlegen.
  Schon eingerichtet? DynoCo startet einfach mit deinen Daten (die bleiben erhalten).
EOF
read -r -p "Eingabetaste zum Schließen …" _
