#!/bin/bash
# Erzeugt telefon/notruf_ton.wav aus profile/$PROFIL/notruf_ton.<ext>.
# Der Ton laeuft im Dialplan vor der Ansage; Taste 1 verbindet waehrenddessen
# zu Astra (siehe telefon/freeswitch/notruf_menue.xml.tpl).
# Format wie telefon/ansage.wav: 8 kHz mono PCM16, -3 dB Kopfraum.
#
# Hat das Profil keinen Ton, wird eine alte notruf_ton.wav entfernt. Der
# Dialplan findet dann keine Datei, play_and_get_digits kehrt sofort zurueck
# und der Anruf laeuft direkt zur Ansage - kein Ton, kein Menue.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${PROFIL:-}" ] && [ -f .env ]; then
  PROFIL=$(awk -F= '$1=="PROFIL"{gsub(/"/,"",$2); print $2}' .env)
fi
PROFIL="${PROFIL:-praxis}"

QUELLE=""
for ext in m4a ogg mp3 wav aiff; do
  if [ -f "profile/$PROFIL/notruf_ton.$ext" ]; then
    QUELLE="profile/$PROFIL/notruf_ton.$ext"
    break
  fi
done

if [ -z "$QUELLE" ]; then
  rm -f telefon/notruf_ton.wav
  echo "Kein Notruf-Ton im Profil $PROFIL - telefon/notruf_ton.wav entfernt (kein Menue)."
  exit 0
fi

ffmpeg -v error -y -i "$QUELLE" -af volume=-3dB -ar 8000 -ac 1 -c:a pcm_s16le telefon/notruf_ton.wav
DAUER=$(ffprobe -v error -show_entries format=duration -of csv=p=0 telefon/notruf_ton.wav)
printf 'telefon/notruf_ton.wav erzeugt (%.1f s, %s)\n' "$DAUER" "$QUELLE"
