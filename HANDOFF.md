# Handoff — Live-Telefonagent (laufend, zuletzt aktualisiert 2026-09-13 Tag)

## Stand in einem Satz

Externer Anruf auf einer echten Durchwahl (9/rufagent) erreicht jetzt zuverlässig Astra über den vollen Weg (Plusnet → FreeSWITCH → `dialog/pipecat_bootstrap.py` → WebSocket → Astra) — offen ist, dass Astra dem Anrufer nach dem ersten "Einen Moment bitte" keine fertige Antwort mehr liefert, bevor der Anrufer auflegt (Details unten, neuer Hauptpunkt für morgen).

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

## Neuer Hauptpunkt für morgen: keine fertige Antwort am Telefon

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
- **Astras Live-Log**: `/private/tmp/astra_server.log` auf minim4-1 (NICHT
  `.runtime/server.log` - das ist ein alter, verwaister Lauf). Bei Zweifel,
  wohin ein laufender Prozess loggt: `lsof -p <pid> -a -d 0,1,2`.
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
