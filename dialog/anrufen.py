"""Outbound-Call-Trigger fuer die Pipecat-Testleitung.

Ruft eine Nummer ueber den Plusnet-Trunk an und uebergibt sie nach Abheben an
dieselbe Bruecke wie die interne Testnebenstelle 7501
(dialog/pipecat_bootstrap.py, Port 8095) - answer()+uuid_audio_stream+park()
laeuft dort identisch, unabhaengig davon ob der Anruf rein- oder rausgeht. Der
Dialplan-Umweg (Nebenstelle 7501) entfaellt hier: `&socket(...)` haengt den
ausgehenden Kanal direkt nach Abheben an den Bootstrap, ohne Dialplan-Lookup.

Nutzung: python3 -m dialog.anrufen <Nummer>
"""

import os
import sys

import greenswitch

FS_HOST = "127.0.0.1"
FS_PORT = int(os.environ.get("FS_PORT", "8022"))
FS_ESL_PASSWORD = os.environ.get("FS_ESL_PASSWORD", "ClueCon")
BOOTSTRAP_PORT = int(os.environ.get("PIPECAT_BOOTSTRAP_PORT", "8095"))
# DW9 ("rufagent") - the only account confirmed capable of outbound so far.
# Needs "proxy" (R-URI domain, must be sip.plusnet.de - Plusnet 403s otherwise)
# split from "outbound-proxy" (actual packet routing, sbc.sip.plusnet.de) in
# its gateway XML - see sip_profiles/external/agentzwei_sbc.xml.
GATEWAY = os.environ.get("ANRUF_GATEWAY", "agentzwei_sbc")
CALLER_ID = os.environ.get("ANRUF_CALLER_ID", "+49210378916179")


def normalisiere(nummer: str) -> str:
    """Wie pipe/kontakte.py: nur Ziffern, Deutschland-Annahme 0 -> 49,
    kein '+' - so erwartet es der Trunk auch fuer DW3_DDI in der .env."""
    ziffern = "".join(zeichen for zeichen in nummer if zeichen.isdigit() or zeichen == "+")
    if ziffern.startswith("+"):
        return ziffern[1:]
    if ziffern.startswith("00"):
        return ziffern[2:]
    if ziffern.startswith("0"):
        return "49" + ziffern[1:]
    return ziffern


def main():
    if len(sys.argv) != 2:
        sys.exit("Nutzung: python3 -m dialog.anrufen <Nummer>")
    ziel = normalisiere(sys.argv[1])
    # The &socket(...) part MUST stay in single quotes: originate splits its
    # arguments on spaces, so an unquoted "&socket(127.0.0.1:8095 async full)"
    # reaches the channel as plain "socket(127.0.0.1:8095)" - "async full"
    # silently dropped (seen in freeswitch.log's own EXECUTE line, 2026-09-13).
    # Without "full", mod_event_socket refuses every command past sendmsg on
    # an outbound listener, so pipecat_bootstrap's CUSTOM-event subscription
    # ("event plain CUSTOM mod_audio_stream::play") is answered with
    # "-ERR command not found" and no audio is ever played back.
    befehl = (
        f"originate {{origination_caller_id_number={CALLER_ID}}}"
        f"sofia/gateway/{GATEWAY}/{ziel} "
        f"'&socket({FS_HOST}:{BOOTSTRAP_PORT} async full)'"
    )
    print(f"Rufe {ziel} an ueber: {befehl}")
    fs = greenswitch.InboundESL(host=FS_HOST, port=FS_PORT, password=FS_ESL_PASSWORD)
    fs.connect()
    antwort = fs.send(f"api {befehl}")
    print(antwort.data)


if __name__ == "__main__":
    main()
