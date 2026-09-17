<include>
  <!-- Anrufbeantworter der Praxis: annehmen, Ansage, aufnehmen, auflegen.
       Die Aufnahme landet im Eingang der Pipe; der Dateiname traegt Zeit und
       Rufnummer (CLIP), damit pipe.watch beides uebernehmen kann. -->
  <extension name="praxis_anrufbeantworter">
    <condition field="destination_number" expression="^.*$">
      <action application="set" data="record_stereo=false"/>
      <action application="set" data="RECORD_ANSWER_REQ=true"/>
      <action application="answer"/>
      <!-- kurze Pause, sonst schneidet die Gegenstelle den Anfang der Ansage ab -->
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
      <!-- record: <datei> <max_sekunden> <stille_schwelle> <stille_sekunden> -->
      <action application="record"
              data="@@PROJEKT@@/telefon/eingang/${strftime(%Y%m%d-%H%M%S)}_${caller_id_number}.wav 120 200 4"/>
      <action application="hangup"/>
    </condition>
  </extension>
</include>
