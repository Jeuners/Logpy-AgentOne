<include>
  <!-- Eigener Kontext fuer die Tastenwahl waehrend der Ansage auf der
       Hauptnummer. 00_praxis_ab.xml spielt telefon/ansage.wav per
       play_and_get_digits und ruft danach
         execute_extension hauptnummer_taste_${hauptnummer_taste} XML hauptnummer_menue
       auf. Nur "hauptnummer_taste_9" hat hier eine Regel; ohne Taste findet
       execute_extension nichts, kehrt zurueck und die Aufnahme startet.

       Bewusst nicht im Kontext "public": dort matcht der Catch-all in
       00_praxis_ab.xml jede Nummer und wuerde die Wahl verschlucken.
       Liegt als Top-Level-Datei unter dialplan/ (wie agentzwei.xml), sonst
       kennt FreeSWITCH den Kontextnamen nicht.

       Taste 9 -> Astra, genau wie Durchwahl 9 (00_dw9_rufagent.xml). Kein
       hangup danach: laeuft der Pipecat-Bootstrap nicht, kehrt socket sofort
       zurueck und der Anrufer landet wenigstens auf dem Anrufbeantworter. -->
  <context name="hauptnummer_menue">
    <extension name="hauptnummer_taste_9">
      <condition field="destination_number" expression="^hauptnummer_taste_9$">
        <action application="socket" data="127.0.0.1:8095 async full"/>
      </condition>
    </extension>
  </context>
</include>
