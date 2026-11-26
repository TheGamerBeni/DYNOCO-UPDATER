#!/bin/bash
# DynoCo-Datenbank auf einem eigenen oder gemieteten Linux-Server (Ubuntu 24.04 / Debian 12).
# Weg A vom 26.11.2026: Die Daten bleiben auf eurem Server, alle Rechner verbinden sich
# verschlüsselt übers Internet (auch von zu Hause).
#
# Einrichten (als root, auf dem Server):
#   bash <(curl -fsSL https://thegamerbeni.github.io/DYNOCO-UPDATER/server.sh) dynoco.beispiel.de
#
# Was passiert:
#   1. Docker, Node und Firewall (nur SSH, 80, 443 offen), automatische Sicherheits-Updates
#   2. die neueste DynoCo-Fassung (Datenbank-Paket) laden und prüfen
#   3. Datenbank einrichten – nur auf diesem Server selbst erreichbar
#   4. Verschlüsselung: Caddy holt das Zertifikat für die Adresse selbst (Let's Encrypt)
#   5. jede Nacht eine Sicherung (14 Tage), jede Stunde der Blick nach einer neuen Fassung
#
# Darf beliebig oft laufen. Bestehende Daten bleiben erhalten.
# Weitere Aufrufe (macht der Server selbst):  dynoco-verwalten aktualisieren | sichern
set -euo pipefail

RELEASE_API="${DYNOCO_RELEASE_API:-https://api.github.com/repos/TheGamerBeni/DYNOCO-UPDATER/releases/latest}"
# Die Ordner lassen sich nur für die automatischen Tests umlenken.
BASE="${DYNOCO_TEST_BASE:-/opt/dynoco}"
DATA="${DYNOCO_TEST_DATA:-/var/lib/dynoco}"
BACKUPS="${DYNOCO_TEST_BACKUPS:-/var/backups/dynoco}"
LOG="${DYNOCO_TEST_LOG:-/var/log/dynoco.log}"
PORT=8787
SELF="${DYNOCO_TEST_SELF:-/usr/local/sbin/dynoco-verwalten}"

say() { printf '\n== %s ==\n' "$1"; }
stop() { printf '\nABBRUCH: %s\n' "$1" >&2; exit 1; }
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG"; }

[ "$(id -u)" = 0 ] || stop "Bitte als root ausführen (z. B. nach „ssh root@<Server>“)."

node_bin() { echo "$BASE/node/bin/node"; }
dynoco() { "$(node_bin)" "$BASE/aktuell/server/dynoco-server.mjs" "$@" --data-dir "$DATA"; }

# --- Node (für das Werkzeug des Datenbank-Pakets) -----------------------------------------
install_node() {
  local arch file sums
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) stop "Unbekannter Prozessor: $(uname -m)" ;;
  esac
  if [ -x "$(node_bin)" ] && "$(node_bin)" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
    echo "Node ist da: $("$(node_bin)" --version)"
    return
  fi
  sums="$(curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt)" || stop "nodejs.org antwortet nicht."
  file="$(printf '%s\n' "$sums" | grep -o "node-v22\.[0-9.]*-linux-${arch}\.tar\.xz" | head -1)"
  [ -n "$file" ] || stop "Keine passende Node-Fassung gefunden."
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/$file" "https://nodejs.org/dist/latest-v22.x/$file" || stop "Node konnte nicht geladen werden."
  (cd "$tmp" && printf '%s\n' "$sums" | grep " ${file}\$" | sha256sum -c --quiet -) || stop "Node: Prüfsumme stimmt nicht."
  rm -rf "$BASE/node.neu"
  mkdir -p "$BASE/node.neu"
  tar -xJf "$tmp/$file" -C "$BASE/node.neu" --strip-components=1
  rm -rf "$BASE/node" && mv "$BASE/node.neu" "$BASE/node"
  rm -rf "$tmp"
  echo "Node installiert: $("$(node_bin)" --version)"
}

# --- Neueste Fassung des Datenbank-Pakets ------------------------------------------------
# Gibt „<Version> <Adresse> <sha256>“ aus.
latest_release() {
  curl -fsSL -H 'Accept: application/vnd.github+json' "$RELEASE_API" | "$(node_bin)" -e '
    let text = "";
    process.stdin.on("data", (chunk) => (text += chunk));
    process.stdin.on("end", () => {
      const release = JSON.parse(text);
      const version = String(release.tag_name || "").replace(/^v/, "");
      const asset = (release.assets || []).find((a) => a.name === `DynoCo-${version}-server.tar.gz`);
      if (!/^\d+\.\d+\.\d+$/.test(version) || !asset) process.exit(2);
      const sha = String(asset.digest || "").replace(/^sha256:/, "");
      console.log(`${version} ${asset.browser_download_url} ${sha}`);
    });'
}

installed_version() { cat "$BASE/aktuell/VERSION" 2>/dev/null || echo "keine"; }

# Lädt und prüft eine Fassung nach $BASE/versionen/<Version>.
fetch_version() {
  local version="$1" url="$2" sha="$3" tmp
  [ -d "$BASE/versionen/$version" ] && return 0
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/paket.tar.gz" "$url" || { rm -rf "$tmp"; return 1; }
  if [ -n "$sha" ]; then
    echo "$sha  $tmp/paket.tar.gz" | sha256sum -c --quiet - || { rm -rf "$tmp"; echo "Prüfsumme stimmt nicht."; return 1; }
  fi
  mkdir -p "$BASE/versionen/$version.neu"
  tar -xzf "$tmp/paket.tar.gz" -C "$BASE/versionen/$version.neu"
  echo "$version" >"$BASE/versionen/$version.neu/VERSION"
  mv "$BASE/versionen/$version.neu" "$BASE/versionen/$version"
  rm -rf "$tmp"
}

switch_to() { ln -sfn "$BASE/versionen/$1" "$BASE/aktuell.neu" && mv -T "$BASE/aktuell.neu" "$BASE/aktuell"; }

# --- Nachts: Sicherung --------------------------------------------------------------------
sichern() {
  mkdir -p "$BACKUPS" && chmod 700 "$BACKUPS"
  if dynoco backup --to "$BACKUPS" >>"$LOG" 2>&1; then
    log "Sicherung fertig."
  else
    log "FEHLER: Sicherung fehlgeschlagen."
  fi
  find "$BACKUPS" -name 'dynoco-sicherung-*.dump' -mtime +14 -delete
}

# --- Nachts: Update auf die neueste Fassung ------------------------------------------------
aktualisieren() {
  local line version url sha old
  line="$(latest_release)" || { log "Update: GitHub antwortet nicht."; return 0; }
  read -r version url sha <<<"$line"
  old="$(installed_version)"
  if [ "$old" = "$version" ]; then return 0; fi
  # Nur nach vorne: eine ältere Fassung wird nie eingespielt.
  if [ "$old" != "keine" ] && [ "$(printf '%s\n%s\n' "$old" "$version" | sort -V | tail -1)" = "$old" ]; then
    return 0
  fi
  log "Update von $old auf $version beginnt."
  fetch_version "$version" "$url" "$sha" >>"$LOG" 2>&1 || { log "FEHLER: Fassung $version ließ sich nicht laden."; return 0; }
  sichern
  switch_to "$version"
  if dynoco update >>"$LOG" 2>&1; then
    log "Update auf $version fertig."
    cp "$BASE/aktuell/server/einrichten-server.sh" "$SELF" 2>/dev/null && chmod 755 "$SELF"
  else
    log "FEHLER: Update auf $version fehlgeschlagen – zurück auf $old."
    [ "$old" != "keine" ] && switch_to "$old" && dynoco start >>"$LOG" 2>&1
  fi
}

case "${1:-}" in
  aktualisieren) aktualisieren; exit 0 ;;
  sichern) sichern; exit 0 ;;
esac

# =========================================================================================
# Einrichten
# =========================================================================================
DOMAIN="${1:-}"
[ -n "$DOMAIN" ] || stop "Bitte die Internetadresse des Servers anhängen, z. B.: … server.sh) dynoco.beispiel.de"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%/}"
[[ "$DOMAIN" =~ ^([a-z0-9-]+\.)+[a-z]{2,}$ ]] || stop "„$DOMAIN“ ist keine gültige Internetadresse (Beispiel: dynoco.beispiel.de)."

. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
  ubuntu | debian) ;;
  *) stop "Dieses Skript ist für Ubuntu oder Debian gemacht (gefunden: ${PRETTY_NAME:-unbekannt})." ;;
esac

mkdir -p "$BASE/versionen" "$DATA" "$BACKUPS"
chmod 700 "$DATA" "$BACKUPS"
touch "$LOG" && chmod 600 "$LOG"

say "1 von 5: Grundausstattung (Docker, Firewall, Sicherheits-Updates)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl xz-utils ufw unattended-upgrades >/dev/null
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  echo "Docker wird installiert …"
  curl -fsSL https://get.docker.com | sh >/dev/null || stop "Docker ließ sich nicht installieren."
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker info >/dev/null 2>&1 || stop "Docker läuft nicht."
# Firewall: nur SSH (auf allen Anschlüssen, auf denen es gerade lauscht), 80 und 443.
for ssh_port in $(ss -tlnpH 2>/dev/null | grep -E 'sshd' | grep -oE ':[0-9]+ ' | tr -d ': ' | sort -u); do
  ufw allow "$ssh_port/tcp" >/dev/null
done
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
echo "Firewall an: nur SSH, 80 und 443 sind offen."

say "2 von 5: Node und die neueste DynoCo-Fassung"
install_node
line="$(latest_release)" || stop "Auf GitHub ist noch keine Fassung mit Datenbank-Paket veröffentlicht (ab 0.2.4)."
read -r version url sha <<<"$line"
fetch_version "$version" "$url" "$sha" || stop "Die Fassung $version ließ sich nicht laden."
switch_to "$version"
echo "DynoCo $version ist bereit."
cp "$BASE/aktuell/server/einrichten-server.sh" "$SELF" && chmod 755 "$SELF"

say "3 von 5: Datenbank einrichten (beim ersten Mal einige Minuten)"
dynoco setup --port "$PORT" --bind 127.0.0.1 --public-url "$DOMAIN" | tee /root/dynoco-einrichtung.txt
chmod 600 /root/dynoco-einrichtung.txt

say "4 von 5: Verschlüsselung für $DOMAIN"
docker rm -f dynoco-https >/dev/null 2>&1 || true
docker run -d --name dynoco-https --restart unless-stopped --network host \
  -v dynoco-https-daten:/data -v dynoco-https-config:/config \
  caddy:2 caddy reverse-proxy --from "$DOMAIN" --to "127.0.0.1:$PORT" >/dev/null \
  || stop "Die Verschlüsselung (Caddy) ließ sich nicht starten."
echo "Warte auf das Zertifikat (bis zu 2 Minuten) …"
ok=""
for _ in $(seq 1 24); do
  # Jede Antwort über eine gültige Verschlüsselung zählt (ohne Schlüssel antwortet die
  # Schnittstelle mit 401). „000“ heißt: keine Verbindung oder kein gültiges Zertifikat.
  answer="$(curl -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN/rest/v1/" 2>/dev/null || true)"
  if [ -n "$answer" ] && [ "$answer" != "000" ]; then
    ok=1
    break
  fi
  sleep 5
done
if [ -z "$ok" ]; then
  echo "ACHTUNG: https://$DOMAIN antwortet noch nicht verschlüsselt."
  echo "Zeigt die Adresse $DOMAIN wirklich auf diesen Server (DNS-Eintrag)? Sind 80 und 443"
  echo "beim Anbieter freigegeben? Danach dieses Skript einfach noch einmal starten."
else
  echo "https://$DOMAIN ist verschlüsselt erreichbar."
fi

say "5 von 5: Sicherung jede Nacht, Updates jede Stunde"
cat >/etc/cron.d/dynoco <<CRON
# DynoCo: Sicherung jede Nacht um 2:30 (14 Tage aufbewahrt). Jede Stunde nach einer neuen
# Fassung sehen – vor jedem Update wird zusätzlich gesichert.
30 2 * * * root $SELF sichern
17 * * * * root $SELF aktualisieren
CRON
chmod 644 /etc/cron.d/dynoco
echo "Eingerichtet. Sicherungen liegen in $BACKUPS, das Protokoll in $LOG."

cat <<TEXT

Fertig. So geht es weiter:
  1. Auf jedem Rechner DynoCo installieren und „Weiterer Rechner“ wählen.
  2. Den Verbindungscode von oben einfügen (er steht auch in /root/dynoco-einrichtung.txt).
  3. Der erste Rechner: bei „Anmelden“ auf „Ich habe einen Zugangsschlüssel“ und den
     ersten Zugangsschlüssel von oben einlösen. Danach bist du Inhaber.
TEXT
