#!/usr/bin/env python3
"""Assemble native review artifacts without changing game or player data."""
from pathlib import Path
import hashlib
import html
import json
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/solo-story'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    sources = [
        'project.godot', 'default_bus_layout.tres', 'README.md',
        'scripts/game.gd', 'scripts/player.gd', 'scripts/hud.gd',
        'scripts/main_menu_panel.gd', 'scripts/input_setup.gd',
        'scripts/solo_story_catalog.gd', 'scripts/solo_story_state.gd',
        'scripts/solo_story_controller.gd', 'scripts/solo_story_find.gd',
        'scripts/solo_story_npc.gd', 'scripts/solo_story_panel.gd',
        'scripts/story_director.gd', 'scripts/story_objective_panel.gd',
        'scripts/character_catalog.gd', 'scripts/crew_roster.gd',
        'scripts/character_select_panel.gd', 'scripts/network_panel.gd',
        'scripts/worker_visual.gd', 'scripts/actor_ground_shadow.gd',
        'scripts/audio.gd', 'scripts/audio_defaults.gd', 'scripts/audio_bus_mix.gd',
        'scripts/campaign_state.gd', 'scripts/expedition_controller.gd',
        'scripts/offline_campaign_archive.gd', 'scripts/network_protocol.gd',
        'scripts/parallax_landscape.gd', 'scripts/sky_traffic.gd', 'scripts/sky_traffic_catalog.gd',
        'scripts/menu_scenery.gd',
        'scripts/menu_atmosphere.gd', 'scripts/scenario_scenery.gd',
        'shaders/sky_cloud_sampling.gdshaderinc',
        'shaders/sky_traffic_cloud.gdshader', 'shaders/sky_traffic_light.gdshader',
        'locales/de.json', 'locales/en.json', 'tools/check_locales.py',
        'tools/build_solo_story_review.py',
    ]
    reports = [
        'catalog/report.json', 'runtime/report.json',
        'recruits/recruits-review.json', 'ui/gallery/gallery.json',
        'ui/affected-results.json', 'shadows/review.json',
        'offline-resume/test-report.json', 'offline-resume/report.json',
        'audio/defaults-verification.json', 'audio/postfix-review-final.json',
        'audio/mixer-reference-results.json', 'audio/editor-buses/verification.json',
        'audio/editor-buses/review.json', 'audio/final-integrated-results.json',
        'network/online-resume/direct-two/report.json', '../sky-traffic/verification.json',
        'runtime/locales-final.json', 'runtime/final-parser-report.json', 'runtime/final-validation.json',
    ]
    available = {p: {'sha256': digest(OUT / p)} for p in reports if (OUT / p).is_file()}
    network = {}
    for mode in ['direct', 'relay']:
        log = OUT / 'network' / (mode + '-final-driver.log')
        text = log.read_text() if log.is_file() else ''
        network[mode] = {'passed': 'four independent processes passed' in text,
                         'log': str(log.relative_to(OUT)),
                         'scope': 'Four real processes, eight-profile protocol; movement, travel seats, reconnect and finite cargo.'}
    report = {
        'generated_utc': datetime.now(timezone.utc).isoformat(),
        'scope': ['Twelve-site solo narrative and encounters', 'Oskar and Rika identities',
                  'Actual ground shadows', 'One-player offline continuation with parked crew',
                  'Fifty-percent listening defaults and editable authored audio buses/FX',
                  'Distant lights between transparent cloud planes'],
        'narrative': {'chapters': 12, 'authored_entries': 89, 'physical_finds': 24,
                      'recruitable_contacts': 5, 'new_characters': ['oskar', 'rika'],
                      'journal_key': 'J', 'existing_recorded_voice_assets': 142,
                      'new_narrative_presentation': 'Localized text; new character tactical radio explicitly uses existing SAN recordings.'},
        'source_sha256': {p: digest(ROOT / p) for p in sources if (ROOT / p).is_file()},
        'evidence_reports': available,
        'network': network,
        'limits': ['Campaign endpoints and later-wave states are prepared fixtures, not a complete manual campaign playthrough.',
                   'Native galleries use Compatibility/OpenGL on NVIDIA at held camera/actor states.',
                   'Mixer verification captures actual Dummy audio PCM; it does not make a subjective listening claim.',
                   'No frame-rate benchmark or public relay deployment is included.',
                   'Previous reports retain their own source snapshots; this manifest records the final integrated files.'],
    }
    (OUT / 'review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    galleries = [
        ('ui/gallery/index.html', 'Begegnungen und Logbuch', '56 native Aufnahmen · Deutsch/Englisch · 720p/QHD'),
        ('recruits/index.html', 'Oskar und Rika', 'Eigene Pixelgrafik, Gesten und je fünf persönliche Tänze'),
        ('shadows/index.html', 'Schatten am Boden', 'Vergleich auf Gelände, Dach und Dachkante'),
        ('../sky-traffic/index.html', 'Licht zwischen Wolken', 'Transparente Tiefen, dünne Ränder und dichte Wolken'),
        ('audio/editor-buses/index.html', 'Audio und Live-Effekte', 'Gespeicherte Pegel, Hall, Filter, Kompression und echter Exporttest'),
    ]
    links = ''.join(f'<a href="{html.escape(path)}"><strong>{html.escape(title)}</strong><span>{html.escape(detail)}</span></a>'
                    for path, title, detail in galleries)
    figures = [
        ('ui/gallery/encounter-ready-1280-de.png', 'Oskar im Basaltbruch: Aufnahme mit zwei tatsächlichen Betonvorräten. Drei abgewehrte Wellen sind für diese UI-Aufnahme vorbereitet.'),
        ('ui/gallery/journal-find-1280-de.png', 'Ein physischer Fund öffnet genau seinen Eintrag im Logbuch. Zukünftige Kapitel verraten keine ungelesenen Texte.'),
        ('ui/gallery/crew-bottom-1280-de.png', 'Acht Figuren passen in die scrollbare Auswahl; Maus, Tastatur und Controller bleiben bedienbar.'),
    ]
    pictures = ''.join(f'<figure><a href="{path}"><img src="{path}" alt="{html.escape(caption)}" loading="lazy"></a><figcaption>{html.escape(caption)}</figcaption></figure>'
                       for path, caption in figures)
    page = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Das letzte Signal</title><style>
:root{color-scheme:dark;background:#101714;color:#d3d0b8;font:16px/1.6 system-ui,sans-serif}body{max-width:1160px;margin:0 auto;padding:40px 24px}h1{font-size:38px;line-height:1.2;margin:10px 0 22px}h2{font-size:23px;margin:36px 0 12px}.eyebrow{letter-spacing:.16em;color:#b6bf98;font-size:12px}p{max-width:850px}a{color:#e2b565;text-decoration:none}a:hover{text-decoration:underline}nav{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:20px;margin:30px 0}nav a{border-top:1px solid #52634f;padding:15px 0}nav strong,nav span{display:block}nav span,figcaption,small{color:#a4ac99;font-size:14px}figure{margin:28px 0}img{display:block;width:100%;height:auto;background:#080d0b}figcaption{padding:10px 0}table{border-collapse:collapse;margin:18px 0;width:100%;max-width:800px}td,th{text-align:left;padding:10px 14px;border-bottom:1px solid #344438}footer{margin-top:40px;border-top:1px solid #344438;padding-top:15px}code{color:#d3bb8b}</style>
<div class="eyebrow">BUNKERCREW · INTEGRIERTE SPIELANSICHTEN</div><h1>Das letzte Signal</h1>
<p>Zwölf Schauplätze erzählen, wie die Crew das ausgefallene Warnnetz wieder aufbaut. 24 Feldaufzeichnungen und fünf ansprechbare Menschen verbinden die Orte. Oskar und Rika bringen neue Fähigkeiten, eigene Gesten und persönliche Tänze mit.</p>
<p>Im Hauptmenü <b>Solo-Story</b> wählen. <b>E</b> spricht mit einer erreichbaren Person oder liest einen Fund; <b>J</b> öffnet das Logbuch. Eine Aufnahme prüft die tatsächliche Lage und verbraucht vorhandene Vorräte einmal. Gewonnene Crewmitglieder bleiben für spätere Schichten auswählbar.</p>
<nav>LINKS</nav>PICTURES
<h2>Fortsetzen, Schatten und Ton</h2><p>Offline-Fortsetzen lädt genau eine aktive Figur. Die anderen Crewmitglieder behalten Fortschritt, Munition und Vorräte in einer lokalen Sicherung. Ein späteres bewusstes Beitreten stellt sie wieder her; bereits eingelagerte Rohstoffe werden dabei nicht dupliziert.</p>
<p>Ein Sprung lässt den Schatten auf dem tatsächlichen Boden oder Dach. Entfernung, Neigung und Kanten bestimmen seine Größe, Deckkraft und Form. Die entfernten Himmelspunkte liegen zwischen zwei transparenten Wolkenebenen; dichte Bereiche verdecken sie.</p>
<table><thead><tr><th>Kanal</th><th>Neuer Startregler</th><th>Gewählter bisheriger Pegel</th></tr></thead><tbody><tr><td>Musik</td><td>50 %</td><td>80 %</td></tr><tr><td>Effekte</td><td>50 %</td><td>50 %</td></tr><tr><td>Figurensprache</td><td>50 %</td><td>20 %</td></tr><tr><td>Partnersprache</td><td>50 %</td><td>50 %</td></tr></tbody></table>
<p>Das gespeicherte Godot-Bus-Layout bestimmt die Grundmischung; die Spielregler verändern sie relativ dazu. Fünfzig Prozent ist die neutrale Mittelstellung. Gespeicherte Pegel und native Effekte der vier Busse werden in Editor-Testläufen übernommen, auch während einer Pause. Hall, Filter und Kompression lassen sich hinzufügen, entfernen, aktivieren und abstimmen. Der Ausgangsbegrenzer bleibt hinter der Verstärkung, und persönliche Einstellungen bleiben separat.</p>
<h2>Prüfbare Nachweise</h2><p><a href="review.json">Quellen und Umfang</a> · <a href="offline-resume/test-report.json">Koop → Offline und Vorräte</a> · <a href="audio/defaults-verification.json">Startpegel und gemischte Audiosamples</a> · <a href="audio/editor-buses/verification.json">Editor-Pegel und laufende FX-Übernahme</a> · <a href="runtime/final-validation.json">Abschließende Prüfungen</a></p>
<p><small>Die Aufnahmen zeigen echte Godot-Szenen in vorbereiteten Zuständen. Spätere Wellen, sichere Begegnungen und Kampagnenenden sind Prüfzustände; kein vollständiger manueller Kampagnendurchlauf. Neue Geschichte: deutsche und englische Texte. Die bestehenden Sprachaufnahmen bleiben erhalten; Oskar und Rika nutzen ausdrücklich SAN-Funk.</small></p>
<footer><a href="../../README.md">Projektanleitung</a> · Native Compatibility-Aufnahmen und echte AudioServer-Samples; keine Änderungen an persönlichen Spielständen oder öffentlichen Diensten.</footer></html>'''
    (OUT / 'index.html').write_text(page.replace('LINKS', links).replace('PICTURES', pictures))
    print('SOLO STORY REVIEW:', len(report['source_sha256']), 'source hashes,', len(available), 'evidence reports')


if __name__ == '__main__':
    main()
