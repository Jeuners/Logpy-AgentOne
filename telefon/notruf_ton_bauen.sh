#!/bin/bash
# Erzeugt telefon/notruf_ton.wav aus profile/$PROFIL/notruf_ton.<ext>.
# Der Ton laeuft im Dialplan vor der Ansage; Taste 1 verbindet waehrenddessen
# zu Astra (siehe telefon/freeswitch/notruf_menue.xml.tpl).
# Format wie telefon/ansage.wav: 8 kHz mono PCM16 (Aufbereitung siehe unten).
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

# Fuer die Leitung aufbereiten, nicht nur umrechnen. Der Ton ist Musik mit
# viel Bass (am 2026-09-17 gemessen: fast die ganze Energie unter 300 Hz,
# im Telefonband 300-3400 Hz nur -25 dB). Das Telefon wirft den Bass weg, der
# Rest klang duenn und kaputt; Mobilfunk-Sprachcodecs (AMR/EVS) verschmieren
# Bass und Schlagzeug zusaetzlich. Deshalb:
#   - Mono-Mix (Seitensignal ist ~22 dB leiser, geht nichts verloren)
#   - Band 300-3300 Hz steil begrenzen (je zwei 2-Pol-Filter)
#   - +4 dB bei 1800 Hz, damit die Melodie traegt
#   - Kompressor + Limiter bei -6 dB: gleichmaessig laut, keine Spitzen,
#     die Provider oder Endgeraet uebersteuern
# Ergebnis: im Telefonband ~8,5 dB lauter als die reine Umrechnung.
ffmpeg -v error -y -i "$QUELLE" -af "\
pan=mono|c0=0.5*c0+0.5*c1,\
highpass=f=300:poles=2,highpass=f=300:poles=2,\
lowpass=f=3300:poles=2,lowpass=f=3300:poles=2,\
equalizer=f=1800:t=o:w=1.5:g=4,\
acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=4,\
alimiter=limit=0.5:level=disabled:attack=3:release=60,\
aresample=8000:filter_size=64:cutoff=0.97" \
  -ac 1 -c:a pcm_s16le telefon/notruf_ton.wav
DAUER=$(ffprobe -v error -show_entries format=duration -of csv=p=0 telefon/notruf_ton.wav)
printf 'telefon/notruf_ton.wav erzeugt (%.1f s, %s)\n' "$DAUER" "$QUELLE"
