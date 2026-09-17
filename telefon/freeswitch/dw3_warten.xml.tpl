<include>
  <!-- Durchwahl 3: Fonial klingelt bei dieser DDI offenbar PARALLEL an
       AgentOne und an MainMacPhone (dem Endgeraet mit Durchwahl 3). Ohne
       diese Regel beantwortet AgentOne jeden Anruf sofort (answer() ist die
       erste Aktion in 00_praxis_ab.xml, keine Verzoegerung davor) - AgentOne
       gewinnt das Rennen daher immer, bevor am anderen Mac ueberhaupt
       geklingelt hat. deflect() (siptrace-verifiziert: nie tatsaechlich ein
       302 verschickt) hat rein zufaellig als Wartezeit gewirkt und damit
       MainMacPhone eine Chance gegeben.
       Diese Regel macht das Warten explizit: bei erkannter DW3
       (X-ORIGINAL-DDI-URI, da destination_number bei diesem Trunk
       unbrauchbar ist) erstmal nur schlafen. Nimmt jemand an MainMacPhone
       ab, schickt Plusnet ein CANCEL - der Kanal wird beendet, bevor der
       sleep() zu Ende ist, alles Weitere unten laeuft nie. Nimmt niemand ab,
       laeuft der Dialplan nach dem sleep() normal weiter zur Ansage+Aufnahme,
       identisch zu AgentOnes Anrufbeantworter (00_praxis_ab.xml). -->
  <extension name="dw3_warten">
    <condition field="${sip_h_X-ORIGINAL-DDI-URI}" expression="@@DW3_DDI@@">
      <action application="sleep" data="20000"/>
      <action application="set" data="record_stereo=false"/>
      <action application="set" data="RECORD_ANSWER_REQ=true"/>
      <action application="answer"/>
      <action application="sleep" data="700"/>
      <!-- Notruf-Ton (telefon/notruf_ton.wav, nur wenn das Profil einen hat,
           siehe telefon/notruf_ton_bauen.sh). Taste 1 waehrend des Tons oder
           bis 3 s danach -> Astra, siehe notruf_menue.xml.tpl. Sonst weiter
           zur Ansage. Argumente: min max versuche timeout_ms terminator
           datei datei_bei_fehleingabe variable regex ziffern_timeout_ms -->
      <action application="play_and_get_digits"
              data="1 1 1 3000 # @@PROJEKT@@/telefon/notruf_ton.wav silence_stream://250 notruf_taste ^1$ 3000"/>
      <action application="execute_extension" data="notruf_taste_${notruf_taste} XML notruf_menue"/>
      <action application="playback" data="@@PROJEKT@@/telefon/ansage.wav"/>
      <action application="record"
              data="@@PROJEKT@@/telefon/eingang/${strftime(%Y%m%d-%H%M%S)}_${caller_id_number}.wav 120 200 4"/>
      <action application="hangup"/>
    </condition>
  </extension>
</include>
