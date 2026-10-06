# Pflanzen und kleine Wildtiere

Zwei unveränderte, mit dem eingebauten `image_gen.imagegen` erzeugte PNG-Atlanten
erweitern die vorhandenen Baumgrafiken. Beide Originale haben 1254 × 1254 Pixel
und einen echten transparenten Alphakanal. Die vollständigen Prompts,
Werkzeugangaben und vermessenen Ausschnitte stehen in
[vegetation_v1.source.json](vegetation_v1.source.json) und
[fauna_v1.source.json](fauna_v1.source.json).

`vegetation_v1.png` enthält Farn, Laubgebüsch, Brombeergestrüpp, Wiesengras,
Schilf, Rohrkolben, moosige Wurzeln, Efeu, Trockengras, trockenes Gebüsch,
Dornengestrüpp, Flechtensteine, Frostgras, Schneebüsche, alpine Graspolster
und Pilze. Klimaprofile bestimmen die Mischung, Größe und Dichte pro Schauplatz.

`fauna_v1.png` enthält jeweils vier Bewegungsbilder von Maus, Krähe, Möwe,
Spatz, Frosch, Kaninchen, Nachtfalter und Fledermaus. Im Spiel werden nur
Maus, Frosch und Kaninchen eingesetzt: insgesamt
höchstens ein bis zwei kleine Bodentiere je Schauplatz, mit langen Ruhephasen.
Vögel, Fledermäuse und Falter bleiben ungenutzte Motive im Originalatlas.
Die Metadaten beschreiben
jeden Ausschnitt und seinen eigenen Körper- oder Bodenanker. Eine gemeinsame
Skalierung pro Art hält den Körper beim Wechsel der Flügel- oder Laufpose stabil.
Die Originale werden beim Laden weder verändert noch von der GPU zurückgelesen.

Die Laufzeit verwendet `scripts/living_ecology_catalog.gd`,
`scripts/living_vegetation.gd`, `scripts/fauna_catalog.gd` und
`scripts/living_fauna.gd`. Die neuen Elemente gehören zur Kulisse eines
Schauplatzes und werden beim Szenenwechsel gemeinsam mit ihr entfernt.
Die Exportvorlagen schließen auch die JSON-Metadaten ausdrücklich ein.

Die gerenderte Galerie unter `artifacts/living-ecology/index.html` zeigt
vorbereitete Szenen aller 13 Schauplätze mit und ohne die neuen Elemente,
Nahansichten und die reduzierte Effektstufe.
