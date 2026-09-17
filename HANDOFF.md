# Handoff — Live-Telefonagent (laufend, zuletzt aktualisiert 2026-09-17)

## Stand in einem Satz

Astra ist live auf zwei Wegen erreichbar: direkt über Durchwahl 9 und über die Hauptnummer mit **Taste 9 während der Ansage** (Plusnet → FreeSWITCH → `dialog/pipecat_bootstrap.py` → WebSocket → Astra auf minim4-1, Modell `qwen3.5:4b`). Beides am 2026-09-17 mit echten Anrufen bestätigt. Größter offener Punkt: **Sprachqualität am Telefon ist schlecht** (noch nicht untersucht).

## 2026-09-17 (Abend) — Taste 9 auf der Hauptnummer, Astra-Fakten, Offenes

### Taste 9 während der Ansage → Astra (Commit `7c85f91`)

`00_praxis_ab.xml` spielt `telefon/ansage.wav` jetzt per
`play_and_get_digits` (Regex `^9$`, 200 ms Nachlauf) statt `playback` und
ruft danach `execute_extension hauptnummer_taste_${hauptnummer_taste} XML
hauptnummer_menue` auf. Nur `hauptnummer_taste_9` existiert dort →
`socket 127.0.0.1:8095 async full`, identisch zu DW9. Ohne Taste findet
`execute_extension` nichts und die Aufnahme startet wie bisher.

- Eigener Kontext `hauptnummer_menue` (`dialplan/hauptnummer_menue.xml`,
  Top-Level wie `agentzwei.xml`), weil der Catch-all in `public` die Wahl
  sonst verschluckt. Vorlage `telefon/freeswitch/hauptnummer_menue.xml.tpl`,
  eingespielt von `einrichten.sh`.
- DW3 und DW9 unverändert (DW3 spielt weiter `playback`, keine Tastenwahl).
- **Andere Taste** (z. B. 5) bricht die Ansage ab und startet sofort die
  Aufnahme - bewusst so gelassen, bei Bedarf ändern.
- Kein `hangup` nach `socket`: läuft der Bootstrap nicht, landet der Anrufer
  auf dem Anrufbeantworter statt in der Stille.
- Verifiziert: Loopback (Taste 9 → Astra-Begrüßung, Taste 5 → Aufnahme) und
  echter Anruf durch den Nutzer ("klappt super").

**Achtung beim Testen:** Jeder Loopback-Test, der bis zur Aufnahme kommt,
legt eine echte Datei in `telefon/eingang/` ab, die `pipe.watch` nach
wenigen Sekunden als Anruf verarbeitet. Sofort löschen oder vor der Aufnahme
auflegen (`uuid_kill`).

### Notruf-Ton: eingebaut und auf Wunsch wieder entfernt

Zwischendurch lief auf der Hauptnummer ein 54-s-Musikton
(`~/Downloads/MARTIN-Notruf_Ton.m4a`) vor der Ansage mit Taste 1 → Astra
(`83b576f`), dann eine Telefonband-Aufbereitung (`60b6154`, zurückgenommen
in `4e7eeab`). Der Nutzer wollte die alte Ansage zurück: komplett revertiert
in `c9bf40d`, Repo und Live-Dialplan waren danach identisch mit Tag
`vor-notruf-ton-2026-09-17` bzw. `ablage/sicherung-vor-notruf-ton-2026-09-17/`.
Erkenntnis falls es wiederkommt: der Ton ist bass-lastige Musik (Energie fast
komplett unter 300 Hz, im Telefonband nur -25 dB) und klingt am Telefon
schlecht - A-law war nicht die Ursache.

### Astra-Fakten (minim4-1)

- **Modell am Telefon: `qwen3.5:4b`** (nicht mehr `granite4.2:8b`), belegt
  im Log (`'title': 'Antwort formulieren', 'detail': 'qwen3.5:4b'`) und über
  `https://minim4-1.tail0f2cb2.ts.net/api/status`.
- **Latenz:** erste Antwort pro Anruf ~5,8 s, danach ~2,3 s - das Vorwärmen
  beim Verbindungsaufbau reicht offenbar nicht ganz.
- **Log:** `~/Desktop/martin-voice-interface/.runtime/server.log` (Prozess
  `uv run python -m astra.server`, gestartet 2026-09-17 15:29).
  `/private/tmp/astra_server.log` ist seit 2026-09-13 tot.
- **SSH auf minim4-1** ist seit 2026-09-17 an ("Entfernte Anmeldung"),
  Schlüssel-Login von minim4-2 funktioniert (`ssh minim4-1`).

### Offen

1. **Sprachqualität am Telefon schlecht** (Nutzer, 2026-09-17, nach Anrufen
   über Taste 9) - nicht untersucht. Kandidaten: TTS (`LocalPocketTTSService`)
   → Resampling auf 8 kHz, `uuid_audio_stream`/Playback-Kette im Bootstrap,
   Codec (Leitung läuft PCMA).
2. **IP-Wechsel-Erkennung** in `starten.sh` noch nie real ausgelöst (nur der
   Profil-Neustart von Hand getestet).
3. **`agentzwei.xml`:** Kommentar sagt "AgentTwo begraben, register=false",
   eingestellt ist `register=true` und der Trunk ist REGED - Anrufe auf DW2
   laufen in einen Kontext ohne Backend. Nicht angefasst.
4. Störungs-Alarm weiterhin nur lokal auf dem Mac mini (siehe 2026-09-14).

**Diagnose-Tipp (Fehlalarm am 2026-09-17):** "DW9 landet auf der Zentrale"
war eine verwählte Hauptnummer. Welche Nummer wirklich gewählt wurde, steht
pro Anruf im FreeSWITCH-Log:
`grep -a "Regex .*\[dw9_rufagent\]" /opt/homebrew/var/log/freeswitch/freeswitch.log | tail`
- DW9 = `sip:+49210378916179@ipfonie.de`, Hauptnummer = `sip:+4921037891617@ipfonie.de`.

## 2026-09-17 — Leitung stumm nach IP-Wechsel, Watchdog-Kinder sterben

**Symptom:** Durchwahl 9 (und die ganze Leitung) nahm nicht ab. Letzter
eingehender Anruf im FreeSWITCH-Log: 2026-09-15 18:05. Trunks trotzdem
REGED/UP.

### 1. Veraltete öffentliche IP im Contact

FreeSWITCH ermittelt die externe IP per STUN nur beim Laden der XML
(`vars.xml`, `stun-set`). Contact an Plusnet war noch `9.246.125.72`,
tatsächlich `217.142.18.120` (Zwangstrennung, 05:17 kurz 408/DOWN).
Registrierung und Pings gehen weiter raus, eingehende INVITEs laufen ins
Leere - kein Fehler im Log.

**Fix:** `starten.sh` vergleicht bei jedem Watchdog-Lauf
`fs_cli -x 'stun stun.freeswitch.org'` mit `Ext-SIP-IP` des
external-Profils; bei Abweichung und 0 Gesprächen `reloadxml` +
`sofia profile external restart`. Nach einem IP-Wechsel ist die Leitung
also bis zu 5 min stumm. Profil-Neustart von Hand getestet (Trunks sofort
wieder REGED); der Abweichungsfall selbst noch nicht real ausgelöst.

### 2. launchd beendete alles, was starten.sh im Hintergrund startet

Vom Watchdog gestarteter Pipecat-Bootstrap band Port 8095 und war
Sekunden später weg, ohne Log. Ursache: launchd räumt nach Jobende die
Prozessgruppe ab. Betraf auch `pipe.monitor`/`pipe.watch`/`pipe.server` -
Fix 3 vom 2026-09-14 (Störungswache zuerst) griff unter launchd also nie.
FreeSWITCH überlebt, weil es sich selbst abkoppelt.

**Fix:** `<key>AbandonProcessGroup</key><true/>` in
`~/Library/LaunchAgents/net.dillenberg.fonagent.plist` (liegt **nicht** im
Repo), per `launchctl bootout`/`bootstrap` neu geladen. Verifiziert:
Bootstrap per Watchdog gestartet, lebt nach Jobende weiter.

## 2026-09-14 — Leitung nach Neustart ~80 min tot: Watchdog bekam nichts hoch

**Symptom:** Nach einem Neustart des Mac mini (~12:39) blieb die Leitung
(PROFIL=aufzug-notdienst) tot, bis ~13:58 von Hand gestartet wurde. Der
launchd-Watchdog (`~/Library/LaunchAgents/net.dillenberg.fonagent.plist`,
alle 5 min `starten.sh`) versuchte es 11-mal: jeweils "Backgrounding.",
dann "fs_cli antwortet nicht", exit 1. `freeswitch.log` blieb unberührt,
kein Crash-Report. Laut `autostart.log` hat der Watchdog FreeSWITCH **noch
nie** erfolgreich gestartet - bis dahin lief es offenbar immer manuell.

Drei Ursachen, drei Fixes:

### 1. FreeSWITCH stirbt unter launchd an SIGPIPE (Commit `f785ab3`)

macOS' Datenschutz "Lokales Netzwerk" gilt für launchd-Prozesse, nicht für
Terminal-Shells: jedes Senden an eine LAN-Adresse (192.168.x) endet dort mit
`EPIPE`, Internet und 127.0.0.1 gehen. FreeSWITCH fragt beim Start per NAT-PMP
den Router (`192.168.2.1:5351`) - auch mit `-nonatmap`, das schaltet nur das
Port-Mapping ab, nicht die Erkennung. So früh ignoriert FreeSWITCH SIGPIPE noch
nicht -> Prozess tot ~0,5 s nach dem Backgrounding.

Belegt mit einer zweiten FreeSWITCH-Instanz (eigene Ports, keine Gateways) über
einen temporären LaunchAgent: `-nc -rp -nonatmap` stirbt reproduzierbar,
`-nf` endet mit exit 141 (SIGPIPE), mit `-nonat` läuft sie. Unified Log im
Todesmoment: `UserEventAgent: Got local network blocked notification`. Ein
Python-UDP-Test unter launchd: Router -> Errno 32, 9.9.9.9 -> ok.

**Fix:** `-nonat` im FreeSWITCH-Aufruf in `starten.sh`. Kein Verlust - der
Router hat NAT-PMP nie beantwortet (`nat_map status`: UNKNOWN), die externe IP
kommt per STUN.

**Grenze, die bleibt:** Alles, was der Watchdog startet, erreicht **keine
LAN-Geräte**. Heute unkritisch (Trunks übers Internet, Sockets auf 127.0.0.1,
keine lokalen Telefone registriert). Kommen lokale SIP-Telefone o. Ä. dazu,
bricht das unter launchd wieder - dann nicht lange suchen.

**Noch nicht unter echten Bedingungen verifiziert:** `starten.sh` selbst hat
FreeSWITCH mit `-nonat` noch nicht per Watchdog gestartet (solange es läuft,
überspringt das Skript es). Test: FreeSWITCH stoppen, dann
`launchctl kickstart gui/$(id -u)/net.dillenberg.fonagent` - ~1 min Ausfall.

### 2. Pipecat-Bootstrap brach mit ModuleNotFoundError ab (Commit `907f511`)

`starten.sh` startete `dialog.pipecat_bootstrap` mit System-`python3`, dem
`gevent`/`greenswitch` fehlen. Jetzt `.venv/bin/python`. Die übrigen
`pipe.*`-Dienste laufen weiterhin mit System-`python3` (dort vollständig).

### 3. Störungswache lief genau beim Ausfall nicht (Commit `6db89af`)

`pipe.monitor` wurde erst nach Trunk UP gestartet - kam FreeSWITCH nicht hoch,
gab es auch keine Wache und keinen Alarm. Jetzt startet sie als Erstes in
`starten.sh`, noch vor der Vorabprüfung. `pipe.dienste` meldet "FreeSWITCH
läuft nicht" bzw. "Trunk DOWN" selbst.

**Offen:** Der Alarm ist nur eine lokale macOS-Benachrichtigung (`pipe/alarm.py`,
osascript) auf dem Mac mini - wenn dort niemand vor dem Bildschirm sitzt, sieht
ihn keiner. Für eine Notdienst-Leitung bräuchte es einen Push-Kanal nach außen.

## 2026-09-13 (Tag) — Zwei Bugs gefunden und behoben

### 1. Durchwahl 9 landete bei der Praxis-Zentrale statt bei Astra

**Symptom:** externer Anruf auf +49 2103 78916179 (Durchwahl 9, "rufagent" im
Fonial-Portal, Status Online) klingelte durch, aber es meldete sich die
Praxis-Ansage (`00_praxis_ab.xml`) statt Astra.

**Untersuchung:** `${sip_h_X-ORIGINAL-DDI-URI}` kam korrekt mit
`sip:+49210378916179@ipfonie.de` an — die DDI-Erkennung selbst war NICHT das
Problem (anders als zunächst vermutet). Es gab schlicht **keine Dialplan-Regel,
die auf diese DDI reagiert** — nur `00_dw3_warten.xml` (reagiert exklusiv auf
Durchwahl 3) existierte, alles andere fällt durch zu `00_praxis_ab.xml`
(`^.*$`, kein `continue="true"`, matcht daher wortwörtlich jede Nummer).

**Erster Fix-Versuch schlug fehl, zweiter Grund gefunden:** eine neue Regel
in einer Datei namens `00_rufagent_astra.xml` wurde nach `reloadxml` immer
noch nicht erreicht — der Dialplan-Trace (`fs_cli -x "originate ... &echo()"`-
Anrufe mit `call_debug=true` oder `[INFO]`-Log direkt mitlesen) zeigte, dass
die Regel im geparsten Dialplan gar nicht auftauchte. Grund: `public.xml`
bindet den ganzen Ordner per `<X-PRE-PROCESS cmd="include" data="public/*.xml"/>`
**alphabetisch** ein, und `00_praxis_ab.xml`s Catch-all kommt alphabetisch
VOR `00_rufagent_astra.xml` (`p` < `r`) und beendet die Dialplan-Auswertung,
bevor die eigene Regel überhaupt geladen wird.

**Fix:** Datei umbenannt zu `00_dw9_rufagent.xml` (`d` < `p`, sortiert direkt
hinter `00_dw3_warten.xml` und vor `00_praxis_ab.xml`). Als Vorlage ins Repo
übernommen: `telefon/freeswitch/dw9_rufagent.xml.tpl` + `DW9_DDI` in `.env`
+ neuer Block in `telefon/freeswitch/einrichten.sh` (analog zum
DW3-Block) — die Live-Config kommt jetzt wieder komplett aus dem Repo,
reproduzierbar per `einrichten.sh`.

**Lehre für weitere Durchwahlen:** Jede neue `dialplan/public/*.xml`-Regel,
die vor `00_praxis_ab.xml` greifen soll, MUSS einen Dateinamen bekommen, der
alphabetisch vor `p` einsortiert (Konvention: `00_dwN_<name>.xml`, `N` als
Ziffer direkt nach `00_dw`). Sonst wird sie stillschweigend nie erreicht -
kein Fehler, kein Log-Eintrag, sie taucht im Dialplan-Trace einfach nicht auf.

### 2. Telephone.app kann eine DDI-Registrierung stehlen

Telephone.app (macOS-Softphone) lief auf minim4-1 mit den SIP-Zugangsdaten
einer der Fonial-Durchwahlen für manuelles SIP-Debugging (siehe
`/tmp/telephone_call.pcap`-Mitschnitt dort). Läuft es gleichzeitig mit
FreeSWITCHs eigener Registrierung derselben Durchwahl, ist nicht
deterministisch, wer den Anruf bekommt - siehe auch die Warnung in
`telefon/starten.sh` ("Telephone.app LAEUFT - beenden, sonst
Registrierungskonflikt"). Vor jedem externen Testanruf prüfen:
`pgrep -xl Telephone` auf der Maschine, auf der es installiert ist (hier:
minim4-1, nicht minim4-2!), und bei Bedarf beenden.

## GELÖST 2026-09-13: keine fertige Antwort am Telefon

Realer externer Testanruf (2026-09-13, ~12:14 Uhr) mit echtem Sprecher:

- Audio kommt sauber an (Peak ~3000, kein Stille-Artefakt wie bei
  Loopback/Selbstanruf-Tests).
- STT transkribiert korrekt: "kannst du mich hören?", danach "Hallo."
- Astra spielt beide Male nur den Zwischenbescheid **"Einen Moment bitte."**
  - Danach läuft die eigentliche LLM-Antwort (`granite4.2:8b` über Ollama,
    `NativeOllamaService`) im Astra-Log als `'phase': 'running'` weiter,
    wird aber nie fertig:
    - 1. Versuch: nach 4814 ms durch neue erkannte Nutzer-Sprache
      (`VADUserTurnStartStrategy`) abgebrochen (`'phase': 'cancelled'`) -
      der Anrufer hat vermutlich aus Ungeduld nochmal "Hallo" gesagt.
    - 2. Versuch: nach 6002 ms abgebrochen, weil der Anrufer aufgelegt hat
      (`Anruf beendet` direkt danach im Log, keine erneute Nutzer-Sprache).
  - In beiden Fällen: **keine einzige echte Antwort hat es bis zur TTS
    geschafft**, nur der Zwischenbescheid.

**Hypothese:** Kein Barge-in/Echo-Problem (anders als in der vorherigen
Handoff-Version vermutet) - hier ist die reale Sprache eindeutig neu, kein
Echo-Artefakt. Verdacht: `granite4.2:8b` per Ollama ist für die
Telefon-Pipeline schlicht zu langsam (>5s ohne fertige Antwort), der
Anrufer gibt vorher auf. Zu prüfen morgen:
- Ollama-Antwortzeit isoliert messen (gleicher Prompt, gleiches Modell,
  ohne Telefon-Pipeline drumherum) - liegt es am Modell/Backend oder an
  Rechenlast durch parallel laufende STT/TTS-Modelle auf demselben Mac?
- Ob `ASTRA_OLLAMA_URL`/`ASTRA_OLLAMA_BACKENDS` für die Telefonie-Pipeline
  auf ein schnelleres/entlastetes Backend zeigen sollte (siehe README
  "Ollama-Backend wählen").
- Ob ein kürzerer/schnellerer Zwischenbescheid-Rhythmus (z. B. alle 2-3s
  ein weiteres "Moment noch") das gefühlte Hängen entschärfen würde, während
  am eigentlichen Latenzproblem gearbeitet wird.

**Root Cause bestätigt:** `granite4.2:8b` war zwischen dem Server-Start
(01:50 Uhr) und dem Testanruf (12:14 Uhr) aus Ollama verdrängt worden, trotz
`keep_alive: -1` in `astra/core.py::build_request` - `ollama ps` zeigte
davor `"models": []`. Direkt gemessen: kalt `load_duration` ~12,2s, warm
Gesamtdauer <0,9s. Der Anrufer wurde ungeduldig/legte auf, lange bevor die
eigentliche Generierung (nach dem Laden nur ~1s) fertig war.

**Fix:** `astra/server.py::telefon_inbound` feuert jetzt beim
Verbindungsaufbau parallel zur Begrüßung einen Wegwerf-Generate-Aufruf an
Ollama (`_warm_ollama`, fire-and-forget, Fehler werden ignoriert) - der
Kaltstart-Tax landet dadurch während die Begrüßung läuft, nicht während der
ersten echten Antwort. Verifiziert mit echtem externen Testanruf: LLM-Zeit
1355 ms, vollständige Antwort kam durch, keine Abbrüche mehr. Commit
`a66629a` in `martin-voice-interface`.

**Falls das Problem wiederkehrt** (z. B. weil ein anderer Ollama-Verbraucher
zwischen Anrufen ein anderes Modell lädt und `granite4.2:8b` trotzdem wieder
verdrängt wird): `curl http://127.0.0.1:11434/api/ps` vor einem Testanruf
prüfen, ob das Modell geladen ist.

## Weiterhin offen (aus der vorherigen Handoff-Fassung, unverändert)

### Sitzungs-Hänger-Bug (Astra `busy: true` bleibt hängen)

Noch nicht erneut beobachtet/verifiziert heute, aber nicht aktiv behoben -
weiter im Auge behalten: `sessions`-Gate in `astra/server.py` könnte bei
einem nicht sauber geschlossenen WebSocket (z. B. hartes `hupall`) hängen
bleiben, siehe `run_telephony_call`/`_run_pipeline`s Cleanup-Pfad.

## Werkzeuge/Referenzen

- **Test-Nummer** (externe echte Rufnummer, Astra-Testleitung):
  **+49 2103 78916179** (Durchwahl 9 / "rufagent" im Fonial-Portal). Vor dem
  Test: Telephone.app auf minim4-1 beenden, falls es läuft
  (`pgrep -xl Telephone`).
- **Loopback (ext. 7501, kein echtes Telefon)**: nur zum Prüfen der
  Signalisierung/Verkabelung geeignet, liefert IMMER Stille (Peak ~1) - kein
  Ersatz für einen echten Audiotest.
  `ssh minim4-2 "export PATH=/opt/homebrew/bin:\$PATH; fs_cli -P 8022 -p ClueCon -x 'originate loopback/7501 &park()'"`
- **Selbstanruf** (`dialog.anrufen 2`): unzuverlässig, liefert ebenfalls nur
  Stille (bestätigt 2026-09-13) - nicht mehr nötig jetzt, wo DW9 extern
  erreichbar ist.
- **Nach jedem Testanruf auflegen**:
  `ssh minim4-2 "export PATH=/opt/homebrew/bin:\$PATH; fs_cli -P 8022 -p ClueCon -x 'hupall NORMAL_CLEARING'"`
- **FreeSWITCH-Dialplan neu laden** (nach Änderungen in `dialplan/public/`,
  kein Neustart nötig):
  `ssh minim4-2 "export PATH=/opt/homebrew/bin:\$PATH; fs_cli -P 8022 -p ClueCon -x 'reloadxml'"`
- **Astras Live-Log**: `~/Desktop/martin-voice-interface/.runtime/server.log`
  auf minim4-1 (Stand 2026-09-17; `/private/tmp/astra_server.log` ist alt).
  Bei Zweifel, wohin ein laufender Prozess loggt:
  `lsof -p <pid> -a -d 0,1,2`.
- **Astras aktives Modell**: `curl -s https://minim4-1.tail0f2cb2.ts.net/api/status`.
- **Hauptnummer-Menü ohne Telefon testen** (Loopback in den public-Kontext,
  Taste per `uuid_recv_dtmf` auf das B-Bein; Aufnahme-Warnung oben beachten):
  `fs_cli -P 8022 -x 'originate loopback/5555/public &park()'`, dann
  `fs_cli -P 8022 -x "uuid_recv_dtmf <uuid von loopback/5555-b> 9"`.
- **Bootstrap-Log**: `fonagent-one/telefon/pipecat_bootstrap.log` auf
  minim4-2.
- **ESL-Port** auf minim4-2 ist **8022**, nicht der Standard 8021.
- **Astra neu starten** (siehe vorherige Handoff-Fassung im Git-Log für den
  vollständigen Befehl mit `ASTRA_TELEFON_SECRET`/`ASTRA_LOG_LEVEL`).

## Zugangsdaten/Config

- `.env` auf minim4-2 im Projekt (gitignored) — SIP-Zugänge für `plusnet`,
  `agentzwei`, `agentzwei_sbc`, `ASTRA_TELEFON_WS_URL`, jetzt auch
  `DW9_DDI=49210378916179`.
- `ASTRA_TELEFON_SECRET` — nur als Laufzeit-Env-Var gesetzt, nicht in einer
  Datei auf minim4-1 abgelegt. Muss auf beiden Seiten übereinstimmen.

## GELÖST 2026-09-13 (Folgefehler): Begrüßung komplett stumm nach dem Cap-Fix

Der Cap-Fix oben (Puffer auf 12s angehoben) legte einen zweiten, tieferen Bug
frei: `TTSStoppedFrame` erreicht `serialize()` in diesem Transport **nie** -
per Frame-Type-Tracing bestätigt, `FastAPIWebsocketOutputTransport` reicht an
den Serializer nur `OutputAudioRawFrame` und (bei Barge-in) `InterruptionFrame`
durch, `TTSStoppedFrame` wird intern fürs "Bot hat aufgehört zu sprechen"
verbraucht und nie weitergereicht. Der `if isinstance(frame, TTSStoppedFrame)`-
Zweig war also von Anfang an toter Code - geflusht wurde bisher ausschließlich
über die (zu klein bemessene) Cap. Mit der korrigierten, viel höheren Cap
erreichte eine normal lange Antwort (3-4s) diese nie mehr - und ohne den
(toten) TTSStoppedFrame-Pfad flusste dann gar nichts mehr: Astra loggte
Begrüßung + Transkript ganz normal, aber bei FreeSWITCH kam kein einziges
Playback-Event an.

**Fix:** Flush jetzt über ein Inaktivitäts-Timeout (300ms ohne neuen
Audio-Frame) statt über `TTSStoppedFrame`. Da der Idle-Flush aus einem
Hintergrund-Task feuert (nicht aus `serialize()`s Rückgabewert), braucht er
einen eigenen Sendeweg - der Serializer nimmt jetzt zusätzlich zu `notify`
ein `send`-Callable (`websocket.send_text`). Commit `0a0c8d5` in
`martin-voice-interface`.

Live verifiziert (Loopback-Test): 2,88s gesendet, FreeSWITCH spielt 3,02s
vollständig ab ("done playing file") - keine Stille, kein Abschneiden mehr.

## GELÖST 2026-09-13 (weitere Folgefehler): zu lange Antworten + hackige Wiedergabe

Nach dem Idle-Flush-Fix zwei weitere Probleme live gemeldet:

1. **Antworten zu lang** - der Prompt allein ("1-2 kurze Sätze") wurde vom
   Modell ignoriert, Antworten liefen auf 2-3 Sätze und lang genug, um die
   12s-Puffergrenze zu reißen. Fix: harte `num_predict`-Grenze
   (`Settings.telefon_max_tokens`, Standard 40, `ASTRA_TELEFON_MAX_TOKENS`
   env-einstellbar) statt nur einer Bitte im Prompt. Commit `4e6f266`.
2. **Wiedergabe "hackig"** - der 300ms-Idle-Flush (siehe vorheriger Eintrag)
   feuerte bei Mehrsatz-Antworten fast immer VOR dem nächsten Satz, weil die
   Pause zwischen zwei TTS-Satz-Chunks (das LLM muss den nächsten Satz erst
   zu Ende streamen) regelmäßig über 300ms liegt - jeder Satz kam so als
   eigene, einzeln abgespielte Nachricht statt als eine zusammenhängende
   Antwort. Fix: `flush_now()` auf dem Serializer, ausgelöst über
   `run_telephony_call`s `notify()`-Hook genau dann, wenn die Pipeline
   meldet, dass der Bot wirklich fertig gesprochen hat
   (`BotStoppedSpeakingFrame` via den `'state': 'listening'`-Callback) - das
   ist das einzige verlässliche "Antwort fertig"-Signal, da `TTSStoppedFrame`
   selbst `serialize()` nie erreicht (siehe voriger Eintrag). Der
   Idle-Timeout ist jetzt nur noch Fallback (4s statt 300ms). Commit
   `42acca4`.

Live verifiziert: Begrüßung flusht jetzt ~2ms nach echtem Sprechende (statt
vorher 300ms Verzögerung), vollständig, keine Aufteilung.

**Offen für nächsten Test:** ob Mehrsatz-Antworten jetzt tatsächlich flüssig
klingen (nur mit Loopback getestet, das produziert keine echte Sprache für
einen mehrteiligen Dialog) - braucht einen echten Anruf mit echtem Gespräch.

## GELÖST 2026-09-13 (weiterer Folgefehler): Anruf trennt nach ~50s ohne Antwort

Erster echter Mehrsatz-Dialog lief mehrere Runden gut (kurze Antworten,
zusammenhängende Wiedergabe) - dann zweimal hintereinander: VAD hat ausgelöst
(`min_volume=0.3` reagiert absichtlich auch auf leise Signale, siehe
vorheriger Eintrag), aber Nemotron hat für die ganze Runde nichts
transkribiert (`Nemotron result: final, 0 characters`). Ein leeres Transkript
erreicht `LLMUserAggregator` nie als echte Nutzer-Nachricht - keine
LLM-Anfrage, keine Antwort, keine Rückmeldung. Für den Anrufer wirkt das wie
eine tote Leitung; nach zwei solchen Runden hat er aufgelegt.

**Fix:** `NemotronSTTService` bekommt jetzt optional `no_speech_phrases`
(`astra.services.NO_SPEECH_PHRASES`, z. B. "Wie bitte?", "Kannst du das
wiederholen?") und spricht bei leerem finalem Transkript eine davon über
`TTSSpeakFrame`. Nur für die Telefonie verdrahtet (Browser hat schon einen
sichtbaren "listening"-Zustand). Commit `c8946d0`.

**Noch offen:** ob `min_volume=0.3` grundsätzlich zu locker ist (löst zu oft
auf Nicht-Sprache aus) - dieser Fix behandelt nur das Symptom (Anrufer bekommt
immer eine Reaktion), nicht die Ursache. Bei wiederholtem Auftreten:
`ASTRA_TELEFON_VAD_MIN_VOLUME` schrittweise erhöhen und beobachten, ob echte
leise Sprache dann noch erkannt wird.
