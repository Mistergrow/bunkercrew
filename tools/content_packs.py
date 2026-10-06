#!/usr/bin/env python3
"""Scaffold bundled declarative content; validate through the game's real loader."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def scaffold(args) -> None:
    pack_id = args.id
    if not re.fullmatch(r'[a-z0-9][a-z0-9_.-]{0,47}', pack_id) or '..' in pack_id or pack_id == 'bunkercrew.core':
        raise SystemExit('Use a unique lowercase pack ID, for example studio.expansion1.')
    folder = ROOT / 'assets/content' / pack_id
    if folder.exists():
        raise SystemExit(f'Preserving existing pack: {folder}')
    character = json.loads((ROOT / 'assets/content/core/characters.json').read_text())['characters'][2]
    character.update(id=f'{pack_id}:worker', title='WERKSTATTWACHE', detail='Zusätzliche Figur · Profil Ivo', unlocked=True)
    character.pop('starter_slot', None)
    item = {
        'id': f'{pack_id}:component', 'label': 'Zusatzbauteil', 'color': '#afbdad',
        'inventory_order': 100, 'storage': True, 'cargo': True,
        'art': {'kind': 'sprite', 'texture': 'res://assets/workers/material_props.png', 'region': [48, 0, 24, 24]},
    }
    recipe = {
        'id': f'{pack_id}:component_recipe', 'kind': item['id'], 'label': 'ZUSATZBAUTEIL',
        'cost': {'steel': 2}, 'time': 2.0, 'amount': 1, 'note': 'Zusätzlicher Bauplan',
        'art': {'texture': 'res://assets/ui/crafting/crafting_items_v1.png', 'region': [1024, 512, 512, 512]},
    }
    folder.mkdir()
    categories = {'characters': [character], 'items': [item], 'workshop_recipes': [recipe]}
    for kind, rows in categories.items():
        write_json(folder / f'{kind}.json', {kind: rows})
    descriptor = {
        'schema': 1, 'id': pack_id, 'version': '1',
        'requires': [{'id': 'bunkercrew.core', 'version': json.loads((ROOT / 'assets/content/core.json').read_text())['version']}],
        'catalogs': {kind: {'path': f'res://assets/content/{pack_id}/{kind}.json', 'field': kind} for kind in categories},
        'translations': {
            'de': {'Zusätzliche Figur · Profil Ivo': 'Zusätzliche Figur · Profil Ivo', 'Zusatzbauteil': 'Zusatzbauteil',
                   'ZUSATZBAUTEIL': 'ZUSATZBAUTEIL', 'Zusätzlicher Bauplan': 'Zusätzlicher Bauplan', 'WERKSTATTWACHE': 'WERKSTATTWACHE'},
            'en': {'Zusätzliche Figur · Profil Ivo': 'Additional character · Ivo profile', 'Zusatzbauteil': 'Additional component',
                   'ZUSATZBAUTEIL': 'ADDITIONAL COMPONENT', 'Zusätzlicher Bauplan': 'Additional recipe', 'WERKSTATTWACHE': 'WORKSHOP GUARD'},
        },
    }
    write_json(folder / 'pack.json', descriptor)
    (folder / 'AUTHORING.txt').write_text(
        'Authoring template: replace the reused example pictures and character profile with reviewed content before publishing.\n'
        'Record author, source and license beside every new asset. Keep IDs stable after a release.\n', encoding='utf-8')
    if args.enable:
        path = ROOT / 'assets/content/packs.json'
        manifest = json.loads(path.read_text())
        manifest['packs'].append(f'res://assets/content/{pack_id}/pack.json')
        write_json(path, manifest)
    print(f'Created {folder}; ' + ('enabled for the next game start.' if args.enable else 'not enabled.'))


def validate(args) -> None:
    godot = args.godot or os.environ.get('GODOT') or shutil.which('godot')
    if not godot:
        raise SystemExit('Godot 4.7.2 is required.')
    with tempfile.TemporaryDirectory(prefix='bunkercrew-content-preflight-') as temporary:
        base = Path(temporary)
        report = args.report.resolve() if args.report else base / 'content.json'
        report.parent.mkdir(parents=True, exist_ok=True)
        env = {**os.environ, 'XDG_DATA_HOME': str(base / 'data'), 'XDG_CONFIG_HOME': str(base / 'config'), 'XDG_CACHE_HOME': str(base / 'cache')}
        command = [godot, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT), '--script',
                   'tests/content_pack_preflight.gd', '--', '--no-profile-save', '--no-upnp', f'--content-report={report}']
        completed = subprocess.run(command, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        print(completed.stdout, end='')
        if completed.returncode or re.search(r'^(?:SCRIPT ERROR:|ERROR:|WARNING:)', completed.stdout, re.M) or not report.is_file():
            raise SystemExit(1)
        value = json.loads(report.read_text())
        if not value['valid']:
            raise SystemExit(1)
        print(f"Validated {len(value['packs'])} pack(s); content SHA256 {value['content_fingerprint']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    creation = commands.add_parser('scaffold')
    creation.add_argument('id')
    creation.add_argument('--enable', action='store_true', help='Append the new pack to the startup manifest.')
    creation.set_defaults(run=scaffold)
    check = commands.add_parser('validate')
    check.add_argument('--godot')
    check.add_argument('--report', type=Path)
    check.set_defaults(run=validate)
    args = parser.parse_args()
    args.run(args)


if __name__ == '__main__':
    main()
