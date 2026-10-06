extends RefCounted
## Guidance IDs stay local and never enter campaign or network state.
const IDS := ["move", "gather", "wall", "turret", "defend", "production", "excavate", "workshop", "san", "departure", "repair"]
const ENTRIES := {
	"move":{"title":"Deine erste Schicht","body":"Bewege dich mit %s. %s springt; an Leitern geht es nach oben und unten. Die Anleitung folgt deinen echten Aktionen und lässt sich unter %s stoppen."},
	"gather":{"title":"Material aufnehmen","body":"Gehe zur markierten Vorratskiste und halte %s zum Aufnehmen. %s wechselt zwischen nahen Zielen. Materialien liegen wirklich in deinen Händen; die Kiste wird dabei geleert."},
	"wall":{"title":"Die erste Verteidigung","body":"%s\nZum Bauen %s halten. Fertiger Beton muss erst aushärten. Die vorhandenen Vorräte reichen für die erste Mauer; unterirdischer Abbau ist dafür nicht nötig."},
	"turret":{"title":"Das Dachgeschütz","body":"Steige die Leiter zum markierten Geschütz hinauf. %s steigt ein und wieder aus; mit %s feuerst du. Das Geschütz verbraucht echte Munition: leere Magazine mit %s nachladen."},
	"defend":{"title":"Bereit für die erste Welle","body":"Die Front steht. Bereite dein Geschütz vor; %s startet die Warnphase. Verteidige den Kern. Deine Handwaffe schießt mit %s und lädt mit %s nach."},
	"production":{"title":"Nachschub herstellen","body":"Bringe Sand zum Betonmischer oder Erz zum Ofen. %s halten füllt passendes Material ein. Warte auf die fertige Charge und hole sie mit %s ab; ein voller Ausgabepuffer hält die nächste Charge an."},
	"excavate":{"title":"Die erste Etage freigraben","body":"Grabe das markierte Erdreich mit %s frei. Mineraladern liefern Rohstoffe; volle Hände legen den übrigen Ertrag auf den Boden. %s legt Material ab. Erst ein vollständig freigeräumter Arbeitsbereich macht die Werkbank zugänglich."},
	"workshop":{"title":"Dein erster Bauplan","body":"An der Werkbank öffnet %s die Bauplanwahl. Wähle ein Bild, prüfe die Kosten und bestätige die Materiallieferung. Hole den fertigen Auftrag im selben Menü ab. Deine bezahlten Aufträge bleiben beim Wechsel des Bauplans erhalten."},
	"san":{"title":"SAN-1 kennenlernen","body":"Gehe zu SAN-1 am Bunkerkern. Er versorgt Verletzungen automatisch, wenn er dich sicher erreichen kann. Im Technikbaum unter %s lassen sich das Beliefern von Anlagen und das Einsammeln ins Lager getrennt erforschen. Du musst dich zum Lernen nicht verletzen."},
	"departure":{"title":"Gemeinsam auf die Reise","body":"Bereite den Transporter auf der Einsatzkarte vor. %s steigt in einen freien Sitz. Erst die besetzte Crew und der echte Motorstart beginnen die Fahrt. Vorräte und Treibstoff bleiben endlich."},
	"repair":{"title":"Reifenpanne · Reparieren und decken","body":"Gehe zum beschädigten Rad. Halte %s für den Reifenwechsel; bei den Radbolzen kannst du im markierten Zeitfenster antippen oder weiter halten. Begleiter sichern das Fahrzeug. SAN-1 kann beim Wechsel helfen, wenn er am Rad verfügbar ist; Verletzte haben Vorrang. Danach mit %s wieder einsteigen."},
	"repair_cover":{"title":"SAN-1 arbeitet, du verteidigst","body":"SAN-1 ist am Rad und übernimmt den Reifenwechsel. Halte Angreifer vom Fahrzeug fern und bleibe in der Nähe. Verletzte haben bei SAN-1 Vorrang. Sobald das Rad fertig ist, mit %s wieder einsteigen."},
	"full":{"title":"Erst Platz in den Händen schaffen","body":"Deine Hände sind voll. Beliefere eine passende Anlage oder lagere Material in eine Vorratskiste ein. %s wählt das Material; %s legt ein Stück ab, Halten den Stapel. Rohstoffe bleiben auf dem Boden erhalten."},
	"danger":{"title":"Jetzt den Kern verteidigen","body":"Die Bauanleitung wartet bis zur sicheren Pause. Halte die Front, feuere mit %s und lade mit %s nach. Beschädigte Verteidigung kannst du mit passendem Material und %s reparieren."},
	"signal":{"title":"Der Funkauftrag hat Vorrang","body":"%s\nDie Anleitung setzt danach fort; der Auftrag verändert deinen echten Kampagnenfortschritt."},
	"downed":{"title":"SAN-1 braucht einen sicheren Zugang","body":"Du bist verletzt. SAN-1 hilft automatisch, wenn er dich erreichen kann. Die Anleitung wartet auf deine Versorgung; sie verändert weder Gesundheit noch Ausrüstung."}
}

static func contains(id: String) -> bool:
	return id in IDS

static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id,{}).duplicate()
