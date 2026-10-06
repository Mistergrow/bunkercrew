# Sequenz-Studio

Im Hauptmenü **Optionen → Takt → Sequenz-Studio** öffnen. Der Player zeigt die
drei vorhandenen Reiseszenen (Signal, Unwetter und Versorgung) sowie den
Luftkontakt mit ihrer tatsächlichen Spielgrafik, Animation, Sprache und
Effektzuordnung. Er verändert weder die Kampagne noch Freischaltungen.

Die Auswahl bietet alle acht Figuren und alle 13 Schauplätze. **Abspielen**
startet oder pausiert; **Von vorn** startet die Szene neu. Die Zeitleiste pausiert
beim Versetzen und bleibt dabei stumm. Nach **Abspielen** setzen Bild und Sprache
ab der gewählten Stelle fort; bereits vergangene Einzelgeräusche werden nicht
erneut ausgelöst. Das Tempo lässt sich auf 0,25×, 0,5×, 1× und 2× einstellen.
Für die normale Klangbeurteilung 1× verwenden; andere Geschwindigkeiten ändern
auch die Tonhöhe.

**Stumm**, **Untertitel** und **Ruhige Effekte** gelten nur für diese Vorschau.
Die vorhandenen Voice-/SFX-Busse einschließlich ihrer Godot-Effekte und
Lautstärkeregler bleiben maßgeblich. Beim Öffnen pausiert die Menümusik und
setzt beim Schließen an ihrer bisherigen Stelle fort.

Maus, Tab/Shift-Tab und Steuerkreuz bedienen die sichtbaren Elemente. Esc,
Controller-B oder F4 schließen die Vorschau und führen in dieselbe Optionsseite
zurück. Bei geöffneter Auswahlliste schließt Zurück zunächst nur diese Liste.
Die Vorschau ist während einer laufenden Runde deaktiviert.

Die neuen Reisegeräusche liegen mit Generator und Herkunftsangaben in
`assets/audio/travel_cinematics/`; die Brandspur-Grafik des Blitzbaums in
`assets/cinematics/storm_charred_tree_v1.png`. Die Szene verwendet weiterhin
die vorhandenen Sprachaufnahmen und den vorhandenen Fahrzeug-/Figurenstil.

Für einen Hinweis zu Timing oder Szenenwirkung bitte Szene, Figur, Schauplatz,
Sprache, Zeitpunkt auf der Zeitleiste und Standard/reduzierte Effekte nennen.
So lässt sich derselbe Ausschnitt ohne Kampagnendurchlauf wieder aufrufen.
