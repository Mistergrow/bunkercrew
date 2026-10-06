#!/usr/bin/env python3
"""Build the local review page from the native Godot UI capture inventory."""
from __future__ import annotations
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'artifacts/social-ui'
report = json.loads((DEST / 'gallery.json').read_text())
labels = {
    'main-menu': 'Hauptmenü', 'friends-disconnected': 'Freunde ohne Dienst',
    'friends': 'Freundesliste', 'friend-remove-confirm': 'Entfernen bestätigen',
    'friend-requests': 'Freundesanfragen', 'friend-invitations': 'Einladungen',
    'friend-blocked': 'Blockierte Personen', 'lobby': 'Online-Raum',
    'lobby-chat': 'Chat im Raum', 'chat-rejected-draft': 'Entwurf nach Ablehnung',
    'game-chat-feed': 'Kompakter Nachrichtenverlauf',
    'game-chat-composer': 'Chat-Eingabe im Spiel',
    'game-invitation-badge': 'Einladung im laufenden Spiel',
}
entries = sorted(report['captures'], key=lambda e: (e['resolution'][0], e['locale'], list(labels).index(e['id'])))
cards = []
for row in entries:
    path = Path(row['path']).relative_to('artifacts/social-ui').as_posix()
    caption = f"{labels[row['id']]} · {row['locale'].upper()} · {row['resolution'][0]}×{row['resolution'][1]}"
    cards.append(f'<figure data-size="{row["resolution"][0]}" data-lang="{html.escape(row["locale"])}"><a href="{html.escape(path)}"><img loading="lazy" src="{html.escape(path)}" alt="{html.escape(caption)}"></a><figcaption>{html.escape(caption)}</figcaption></figure>')
page = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bunkercrew · Freunde und Chat</title>
<style>body{margin:0;background:#141c18;color:#e0decb;font:16px system-ui,sans-serif}main{max-width:1500px;margin:auto;padding:32px}h1{font-weight:500;color:#d9ac60}p{max-width:1000px;line-height:1.6}a{color:#d9ac60}label{display:inline-block;margin:0 22px 24px 0}select{margin-left:10px;padding:8px;background:#29362f;color:#e0decb;border:1px solid #63726c}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(600px,100%),1fr));gap:24px}figure{margin:0;background:#29362f}figure[hidden]{display:none}img{display:block;width:100%;height:auto}figcaption{padding:12px;color:#a1a18c}.note{border-left:3px solid #d9ac60;padding-left:18px}</style><main>
<h1>Bunkercrew · Freunde und Chat</h1><p>Neue Bedienung im unveränderten Industrie-Stil: Freunde im Hauptmenü und Online-Raum, Einladungen mit Ablaufzeit, Bestätigung vor Entfernen/Blockieren und ein kompakter Chat mit sechs Schnellnachrichten.</p>
<p class="note">Geprüfte vorbereitete Szenenzustände: echte Godot-HUDs und native UI-Knoten mit ausdrücklich eingesetzten Offline-Probes für Dienst-/Raumdaten. Diese Bilder zeigen keine echten Serververbindungen. Die Aufnahme öffnet keine Sockets, schreibt kein Spielerprofil und nimmt kein Mikrofon auf. Deutsch/Englisch, 960×600, 1440×900 und 1920×1080.</p>
<p><a href="gallery.json">Messwerte und sichtbare Controls</a> · <a href="ui-test.log">UI- und Eingabeprüfung</a> · <a href="render-test.log">Vollständige Renderprüfung</a> · <a href="badge-render-test.log">Einladungs-Badge</a></p>
<label>Auflösung<select id="size"><option>960</option><option>1440</option><option selected>1920</option><option value="all">Alle</option></select></label><label>Sprache<select id="lang"><option value="de">Deutsch</option><option value="en">English</option><option value="all">Beide</option></select></label><div class="gallery">'''
page += '\n'.join(cards)
page += '''</div></main><script>function filter(){for(const card of document.querySelectorAll('figure'))card.hidden=(size.value!=='all'&&card.dataset.size!==size.value)||(lang.value!=='all'&&card.dataset.lang!==lang.value)}document.getElementById('size').addEventListener('change',filter);document.getElementById('lang').addEventListener('change',filter);filter()</script></html>'''
(DEST / 'index.html').write_text(page)
(DEST / 'inventory.json').write_text(json.dumps({
    'native_panels': ['scripts/social_panel.gd', 'scripts/chat_panel.gd'],
    'integrations': ['scripts/hud.gd', 'scripts/main_menu_panel.gd', 'scripts/network_panel.gd'],
    'shared_style': 'scripts/ui_art.gd',
    'fonts': ['assets/fonts/bunkercrew/body.tres', 'assets/fonts/bunkercrew/menu.tres', 'assets/fonts/bunkercrew/title.tres'],
    'new_bitmap_assets': [], 'captures': len(entries),
    'capture_command': 'godot --path . --script tests/social_chat_ui_test.gd -- --no-profile-save --no-upnp --capture',
    'fixture': report['fixture'],
}, ensure_ascii=False, indent=2) + '\n')
print(f'Wrote gallery index for {len(entries)} native captures')
