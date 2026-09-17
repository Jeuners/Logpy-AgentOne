<include>
  <!-- Eigener Kontext fuer die Tastenwahl waehrend des Notruf-Tons.
       00_praxis_ab.xml / 00_dw3_warten.xml spielen telefon/notruf_ton.wav per
       play_and_get_digits und rufen danach
         execute_extension notruf_taste_${notruf_taste} XML notruf_menue
       auf. Nur "notruf_taste_1" hat hier eine Regel; ohne Taste (oder bei
       fehlender Ton-Datei) findet execute_extension nichts, kehrt zurueck und
       der Anruf laeuft weiter zu Ansage + Aufnahme.

       Bewusst nicht im Kontext "public": dort matcht der Catch-all in
       00_praxis_ab.xml jede Nummer und wuerde die Wahl verschlucken.
       Liegt als Top-Level-Datei unter dialplan/ (wie agentzwei.xml), sonst
       kennt FreeSWITCH den Kontextnamen nicht.

       Taste 1 -> Astra, genau wie Durchwahl 9 (00_dw9_rufagent.xml). Kein
       hangup danach: laeuft der Pipecat-Bootstrap nicht, kehrt socket sofort
       zurueck und der Anrufer bekommt wenigstens den Anrufbeantworter. -->
  <context name="notruf_menue">
    <extension name="notruf_taste_1">
      <condition field="destination_number" expression="^notruf_taste_1$">
        <action application="socket" data="127.0.0.1:8095 async full"/>
      </condition>
    </extension>
  </context>
</include>
