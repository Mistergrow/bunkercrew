#!/usr/bin/env python3
"""Explicit development/public beta milestones with preserved release history."""
from __future__ import annotations

import argparse
from datetime import date
import json
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NOTES = Path('assets/releases/changelog.json')
VERSION = re.compile(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-beta(?:\.([1-9]\d{7}))?$')


def parse_version(value: str) -> tuple[int, int, int, str]:
    matched = VERSION.fullmatch(value) if isinstance(value, str) else None
    if matched is None:
        raise ValueError('Expected MAJOR.MINOR.PATCH-beta or MAJOR.MINOR.PATCH-beta.YYYYMMDD without leading zeroes')
    major, minor, patch, stamp = matched.groups()
    if stamp is not None:
        date.fromisoformat(f'{stamp[:4]}-{stamp[4:6]}-{stamp[6:]}')
    return int(major), int(minor), int(patch), stamp or ''


def next_release(previous: str, kind: str, release_date: str) -> str:
    major, minor, patch, stamp = parse_version(previous)
    recorded = date.fromisoformat(release_date)
    if kind == 'major': major, minor, patch = major + 1, 0, 0
    elif kind == 'minor': minor, patch = minor + 1, 0
    elif kind == 'patch': patch += 1
    else: raise ValueError('Expected a major, minor or patch increment')
    suffix = '-beta.' + recorded.strftime('%Y%m%d') if stamp else '-beta'
    return f'{major}.{minor}.{patch}{suffix}'


def project_version(root: Path) -> str:
    matched = re.findall(r'^config/version="([^"\n]+)"$', (root / 'project.godot').read_text(), re.M)
    if len(matched) != 1:
        raise ValueError('Project version is missing or ambiguous')
    return matched[0]


def translated_text(value: object) -> bool:
    return (isinstance(value, dict) and set(value) == {'de', 'en'} and
            all(isinstance(text, str) and text.strip() and len(text) <= 1000
                for text in value.values()))


def validate_notes(value: object, current: str) -> dict:
    parse_version(current)
    if not isinstance(value, dict) or value.get('schema') != 1:
        raise ValueError('Release notes require schema 1')
    releases = value.get('releases')
    if not isinstance(releases, list) or not 1 <= len(releases) <= 64:
        raise ValueError('Release notes require 1..64 milestones')
    previous = {}
    previous_date = None
    development_started = False
    for entry in releases:
        if not isinstance(entry, dict) or set(entry) != {'version', 'date', 'title', 'changes'}:
            raise ValueError('Release note entry fields are invalid')
        ordered = parse_version(entry['version'])
        recorded = date.fromisoformat(entry['date'])
        development = bool(ordered[3])
        if development and recorded.strftime('%Y%m%d') != ordered[3]:
            raise ValueError('Beta date and milestone date disagree')
        if not development and development_started:
            raise ValueError('Public beta milestones must precede the dated development history')
        development_started = development_started or development
        if development in previous and ordered >= previous[development]:
            raise ValueError('Milestones must be unique and newest first within their series')
        if previous_date is not None and recorded > previous_date:
            raise ValueError('Milestone dates must be newest first')
        previous[development] = ordered
        previous_date = recorded
        if not translated_text(entry['title']):
            raise ValueError('Every milestone needs a German and English title')
        changes = entry['changes']
        if not isinstance(changes, list) or not 1 <= len(changes) <= 24 or not all(map(translated_text, changes)):
            raise ValueError('Every milestone needs 1..24 German/English changes')
    if releases[0]['version'] != current:
        raise ValueError('Newest changelog milestone must match project.godot')
    return value


def markdown(notes: dict) -> str:
    lines = ['# Bunkercrew · Changelog', '',
             'Generated from [assets/releases/changelog.json](assets/releases/changelog.json). '
             'Use [the explicit milestone tool](docs/versioning.md); gameplay never changes the version.', '']
    for entry in notes['releases']:
        lines += [f"## {entry['version']} · {entry['date']}", '',
                  f"**Deutsch · {entry['title']['de']}**", '']
        lines += ['- ' + change['de'] for change in entry['changes']]
        lines += ['', f"**English · {entry['title']['en']}**", '']
        lines += ['- ' + change['en'] for change in entry['changes']]
        lines += ['']
    return '\n'.join(lines)


def windows_metadata(presets: str, release: str) -> str:
    major, minor, patch, _ = parse_version(release)
    numeric = f'{major}.{minor}.{patch}.0'
    windows = re.findall(r'\[preset\.(\d+)\]\n([^\[]*)', presets)
    result = presets
    for index, section in windows:
        if 'platform="Windows Desktop"' not in section:
            continue
        pattern = re.compile(r'(\[preset\.' + index + r'\.options\]\n)(.*?)(?=\n\[|\Z)', re.S)
        found = pattern.search(result)
        if found is None:
            raise ValueError('Windows preset options are missing')
        options = found.group(2)
        for field in ('file_version', 'product_version'):
            options, count = re.subn(r'^application/' + field + r'="[^"\n]*"$',
                                     f'application/{field}="{numeric}"', options, flags=re.M)
            if count != 1:
                raise ValueError('Windows version metadata is missing or duplicated')
        options = re.sub(r'^application/file_description="[^"\n]*"$',
                         f'application/file_description="Bunkercrew {release}"', options, flags=re.M)
        result = result[:found.start(2)] + options + result[found.end(2):]
    return result


def validate_release(root: Path) -> dict:
    current = project_version(root)
    notes = validate_notes(json.loads((root / NOTES).read_text()), current)
    if (root / 'CHANGELOG.md').read_text() != markdown(notes):
        raise ValueError('CHANGELOG.md does not match the translated release-note source')
    numeric = '.'.join(map(str, parse_version(current)[:3])) + '.0'
    presets = (root / 'export_presets.cfg').read_text()
    for metadata in re.findall(r'^application/(?:file_version|product_version)="([^"\n]*)"$', presets, re.M):
        if metadata and metadata != numeric:
            raise ValueError('Windows metadata does not match the current project version')
    filters = re.findall(r'^include_filter="([^"\n]*)"$', presets, re.M)
    if not filters:
        raise ValueError('Export presets are missing their runtime asset filters')
    for included in filters:
        if NOTES.as_posix() not in included.split(','):
            raise ValueError('Every export preset must ship the local changelog')
    return notes


def commit_files(root: Path, updates: dict[Path, str]) -> None:
    originals = {relative: (root / relative).read_bytes() if (root / relative).exists() else None
                 for relative in updates}
    staged = {}
    written = []
    try:
        for relative, text in updates.items():
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.version-', delete=False) as file:
                file.write(text.encode())
                staged[relative] = Path(file.name)
            os.chmod(staged[relative], target.stat().st_mode & 0o777 if target.exists() else 0o644)
        for relative, original in originals.items():
            actual = (root / relative).read_bytes() if (root / relative).exists() else None
            if actual != original:
                raise ValueError('Source changed while preparing the version milestone')
        for relative, temporary in staged.items():
            os.replace(temporary, root / relative)
            written.append(relative)
    except BaseException:
        for relative in reversed(written):
            if originals[relative] is None:
                (root / relative).unlink()
            else:
                (root / relative).write_bytes(originals[relative])
        raise
    finally:
        for temporary in staged.values():
            temporary.unlink(missing_ok=True)


def bump(root: Path, release: str, title: dict, changes: list[dict], dry_run: bool = False,
         *, start_public_series: bool = False, release_date: str | None = None) -> dict:
    notes = validate_release(root)
    previous = project_version(root)
    target = parse_version(release)
    current = parse_version(previous)
    if start_public_series:
        if not current[3] or target[3] or any(not parse_version(entry['version'])[3]
                                               for entry in notes['releases']):
            raise ValueError('The public beta series can start once, from dated development milestones')
    elif bool(target[3]) != bool(current[3]):
        raise ValueError('A normal milestone must remain in its current series; only the first dated-to-public transition uses --start-public-series')
    elif target <= current:
        raise ValueError('A milestone must increase the version; old packages are never reused')
    stamp = target[3]
    recorded = date.fromisoformat(f'{stamp[:4]}-{stamp[4:6]}-{stamp[6:]}') if stamp else date.fromisoformat(release_date or date.today().isoformat())
    entry = {'version': release, 'date': recorded.isoformat(),
             'title': title, 'changes': changes}
    updated = {'schema': 1, 'releases': [entry] + notes['releases']}
    validate_notes(updated, release)
    project = (root / 'project.godot').read_text().replace(f'config/version="{previous}"', f'config/version="{release}"')
    presets = windows_metadata((root / 'export_presets.cfg').read_text(), release)
    presets = presets.replace(f'export_path="beta/{previous}/', f'export_path="beta/{release}/')
    updates = {Path('project.godot'): project, Path('export_presets.cfg'): presets,
               NOTES: json.dumps(updated, ensure_ascii=False, indent=2) + '\n',
               Path('CHANGELOG.md'): markdown(updated)}
    if not dry_run:
        commit_files(root, updates)
        validate_release(root)
    return {'previous': previous, 'version': release, 'dry_run': dry_run,
            'start_public_series': start_public_series,
            'changed_files': [path.as_posix() for path in updates]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--check', action='store_true')
    actions.add_argument('--bump', choices=('patch', 'minor', 'major'))
    actions.add_argument('--to', dest='release')
    parser.add_argument('--date', default=date.today().isoformat())
    parser.add_argument('--start-public-series', action='store_true',
                        help='Explicitly start the first undated public beta series; historical dated milestones remain unchanged')
    parser.add_argument('--title-de')
    parser.add_argument('--title-en')
    parser.add_argument('--change-de', action='append', default=[])
    parser.add_argument('--change-en', action='append', default=[])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        if args.start_public_series and (args.check or args.bump or not args.release):
            raise ValueError('--start-public-series requires an explicit --to MAJOR.MINOR.PATCH-beta')
        if args.check:
            validate_release(args.root)
            print('VERSION/CHANGELOG PASS: ' + project_version(args.root))
            return
        if not args.title_de or not args.title_en or not args.change_de or len(args.change_de) != len(args.change_en):
            raise ValueError('Supply both titles and matching --change-de/--change-en pairs')
        release = args.release
        if args.bump:
            release = next_release(project_version(args.root), args.bump, args.date)
        result = bump(args.root, release, {'de': args.title_de, 'en': args.title_en},
                      [{'de': de, 'en': en} for de, en in zip(args.change_de, args.change_en)], args.dry_run,
                      start_public_series=args.start_public_series, release_date=args.date)
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
