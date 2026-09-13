<include>
  <!-- Durchwahl 9 (rufagent) -> Astra-Telefonagent, siehe
       dialog/pipecat_bootstrap.py (Port 8095) und
       astra/telephony.py::FreeswitchAudioStreamSerializer.
       Wie bei dw3_warten (dw3_warten.xml.tpl): destination_number ist bei
       diesem Trunk unbrauchbar, die tatsaechlich gewaehlte DDI kommt nur
       ueber den Header X-ORIGINAL-DDI-URI.

       Dateiname wichtig: muss alphabetisch VOR 00_praxis_ab.xml einsortiert
       werden (00_dw9... < 00_praxis...) - public/*.xml wird per
       X-PRE-PROCESS alphabetisch eingebunden, und praxis_ab.xml's Catch-all
       (^.*$, kein continue="true") stoppt die Dialplan-Auswertung sonst
       schon vorher. Am 2026-09-13 gefunden: eine erste Fassung unter dem
       Namen "00_rufagent_astra.xml" wurde nie erreicht, weil "r" nach
       "p" kommt - siehe HANDOFF.md. -->
  <extension name="dw9_rufagent">
    <condition field="${sip_h_X-ORIGINAL-DDI-URI}" expression="@@DW9_DDI@@">
      <action application="socket" data="127.0.0.1:8095 async full"/>
    </condition>
  </extension>
</include>
