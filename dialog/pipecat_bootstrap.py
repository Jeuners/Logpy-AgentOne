"""Outbound-ESL bootstrap for the Pipecat phone-agent test line.

FreeSWITCH's dialplan extension "agentzwei_pipecat_test" (destination_number
7501, dialplan/default/06_agentzwei_pipecat_test.xml, internal test-only, not
reachable from the PSTN) - and now also dialog/anrufen.py's outbound calls -
hand the channel here via `socket(127.0.0.1:PORT async full)`. This process's
job: answer(), tell mod_audio_stream to start streaming the call's audio to
Astra's /telefon/inbound, then stay on the line for as long as the call lasts
to actually play back what Astra sends - the conversation logic itself lives
entirely in Astra's Pipecat pipeline, over the WebSocket that mod_audio_stream
opens outbound to Astra.

mod_audio_stream has no dialplan application, only the ESL API command
`uuid_audio_stream` (confirmed against the module's own source and by
testing). Confirmed by testing (2026-09-12): issuing `uuid_audio_stream` from
this same process - even over a second, separate ESL connection - reliably
fails the WebSocket connect for real external/gateway calls (instant
"connection error", no such issue for the loopback test line). Matches a
known mod_audio_stream issue (amigniter/mod_audio_stream#92): "It's an issue
with using uuid_audio_stream on the same call session uuid as the Python
script that's listening for the WebSocket, separating these processes
resolves the problem." So the command is shelled out to `fs_cli` as a
genuinely separate OS process, not issued from within this one at all.

Second gap found by testing (2026-09-13): mod_audio_stream does NOT play
audio back on its own. Astra's `streamAudio` message only makes it write a
temp WAV file and fire a `mod_audio_stream::play` CUSTOM event containing that
path (audio_streamer_glue.cpp:290-303) - something has to catch that event and
actually play the file. Nothing in the module or the dialplan does this, so
this process stays on the call (instead of returning right after park()) and
plays each file back as the events arrive, until the call hangs up - with the
`playback` application over this same outbound socket. Unlike uuid_audio_stream
that is not an "api" command but an execute-style application call, exactly
like the answer()/park() that already work here, so it does not need the
separate-process detour.

Getting those CUSTOM events delivered at all took two subscriptions plus one
workaround; see run() and event_body_json() for the details.
"""

import json
import logging
import os
import subprocess
import sys

import gevent
import greenswitch

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("pipecat_bootstrap")

BIND_ADDRESS = os.environ.get("PIPECAT_BOOTSTRAP_BIND", "127.0.0.1")
BIND_PORT = int(os.environ.get("PIPECAT_BOOTSTRAP_PORT", "8095"))
ASTRA_WS_URL = os.environ.get("ASTRA_TELEFON_WS_URL", "")
STREAM_MIX_TYPE = "mono"
STREAM_SAMPLE_RATE = "16k"  # matches NemotronSTTService's hard 16 kHz requirement on the Astra side
# Upper bound so a greenlet can never outlive a call FreeSWITCH itself forgot
# to tell us ended - failure mode is "one stray idle greenlet", not a runaway.
MAX_CALL_SECONDS = 30 * 60

FS_HOST = "127.0.0.1"
FS_PORT = os.environ.get("FS_PORT", "8022")
FS_ESL_PASSWORD = os.environ.get("FS_ESL_PASSWORD", "ClueCon")
FS_CLI = os.environ.get("FS_CLI_BIN", "/opt/homebrew/bin/fs_cli")


def fs_cli(command: str) -> str:
    """Run one `api` command via `fs_cli` as its own OS process - see module
    docstring for why commands for this call must not go over this process's
    own outbound-socket connection."""
    result = subprocess.run(
        [FS_CLI, "-H", FS_HOST, "-P", FS_PORT, "-p", FS_ESL_PASSWORD, "-x", command],
        capture_output=True, text=True, timeout=10,
    )
    return (result.stdout or result.stderr).strip()


def event_body_json(event) -> dict | None:
    """Read a FreeSWITCH event's body (the part after the blank line) as JSON.

    greenswitch's ESLEvent.parse_data() only knows "key: value" lines, so an
    event body - mod_audio_stream sends bare JSON, which has no ": " in it -
    is never split off as its own field. It ends up appended to the value of
    whatever header came last, which in plain format is always the body's own
    "Content-Length". So `headers["Content-Length"]` reads e.g.
    '84\\n\\n{"audioDataType":"wav","file":"/tmp/....wav"}' - the payload is
    there, just glued to a number. Cut at the first "{" and parse that.
    """
    raw = event.headers.get("Content-Length") or ""
    start = raw.find("{")
    if start == -1:
        return None
    try:
        payload = json.loads(raw[start:])
    except (ValueError, TypeError):
        return None
    return payload if isinstance(payload, dict) else None


class PipecatBridge:
    """One instance per call, per greenswitch's OutboundESLServer contract."""

    def __init__(self, session):
        self.session = session
        self.call_id = getattr(session, "uuid", "?")
        self.hung_up = gevent.event.Event()

    def on_play_event(self, event):
        payload = event_body_json(event)
        if payload is None:
            logger.warning(
                "Anruf %s: mod_audio_stream::play-Event ohne lesbaren JSON-Rumpf: %r",
                self.call_id, event.headers,
            )
            return
        path = payload.get("file")
        if not path:
            logger.warning("Anruf %s: play-Event ohne Dateipfad: %r", self.call_id, payload)
            return
        # Same mechanism Logpy-AgentOne already uses successfully in
        # production (dialplan `playback` app) - over this session's own
        # connection, unlike uuid_audio_stream this is an "execute"-style
        # application call (like answer()/park(), already proven to work
        # here), not an "api" command.
        self.session.playback(path, block=False)
        logger.info("Anruf %s: spiele %s ab", self.call_id, path)

    def on_hangup(self, event):
        self.hung_up.set()

    def run(self):
        try:
            # Two separate subscriptions, both required, in this order:
            #
            # `myevents` turns on this session's own event feed, but it does
            # NOT mean "all events" - mod_event_socket hardcodes a whitelist
            # of ~23 event ids there (mod_event_socket.c, parse_command(),
            # "myevents" branch), all of them CHANNEL_*/DTMF/TALK. CUSTOM is
            # not in it, so no module's CUSTOM event can ever arrive on a
            # myevents-only socket, no matter its subclass.
            #
            # `event plain CUSTOM <subclass>` adds exactly that: it sets
            # event_list[CUSTOM] plus a subclass entry in the listener's
            # event_hash. It is purely additive - it does not reset the
            # whitelist myevents just installed (only `noevents`/`nixevent`
            # clear entries), so the CHANNEL_* events keep coming. The
            # LFLAG_MYEVENTS flag stays set too, so the CUSTOM events we now
            # get are still filtered down to this channel's own Unique-ID.
            #
            # Needs the socket to be "full" (dialplan/originate say
            # `socket(host:port async full)`): mod_event_socket drops every
            # command past this point for a non-full outbound listener.
            self.session.myevents()
            self.session.send("event plain CUSTOM mod_audio_stream::play")
            self.session.linger()
            self.session.register_handle("mod_audio_stream::play", self.on_play_event)
            self.session.register_handle("CHANNEL_HANGUP", self.on_hangup)
            self.session.answer()
            antwort = fs_cli(
                f"uuid_audio_stream {self.call_id} start {ASTRA_WS_URL} "
                f"{STREAM_MIX_TYPE} {STREAM_SAMPLE_RATE} {self.call_id}"
            )
            logger.info("Anruf %s: uuid_audio_stream gestartet, Antwort: %r", self.call_id, antwort)
            self.session.park()
            # Stay on the line - on_play_event needs to keep firing for the
            # whole call, not just the first bot utterance.
            self.hung_up.wait(timeout=MAX_CALL_SECONDS)
        except Exception:
            logger.exception("Anruf %s: Bootstrap fehlgeschlagen", self.call_id)
        finally:
            self.session.stop()


def main():
    if not ASTRA_WS_URL:
        sys.exit("ASTRA_TELEFON_WS_URL fehlt in der Umgebung (.env) - Abbruch.")
    logger.info("Pipecat-Bootstrap hoert auf %s:%s, Ziel: %s", BIND_ADDRESS, BIND_PORT, ASTRA_WS_URL)
    server = greenswitch.OutboundESLServer(
        bind_address=BIND_ADDRESS, bind_port=BIND_PORT,
        application=PipecatBridge, max_connections=5,
    )
    server.listen()


if __name__ == "__main__":
    main()
