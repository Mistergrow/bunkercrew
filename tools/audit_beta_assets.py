#!/usr/bin/env python3
"""Audit export exclusions without deleting assets or guessing unused functions.

Literal references, bounded filename patterns and runtime JSON are checked.
Open directory prefixes remain explicit review items, never deletion evidence.
Use beta_asset_export_test.gd in each actual export for runtime loading proof.
"""
import argparse
from collections import defaultdict
import fnmatch
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_PANORAMAS = (
    'ash_foundry', 'abandoned_harbor', 'basalt_quarry', 'overgrown_steelworks',
    'frozen_rail_yard', 'iron_canyon', 'flooded_power_station', 'mountain_pass',
    'storm_dam',
)
NONRUNTIME_DIRS = ('artifacts', 'beta', 'reference', 'addons', 'tools', 'server', 'native')
RESOURCE_TEXT = {'.gd', '.tscn', '.tres', '.gdshader', '.gdextension', '.godot'}
RESOURCE_LITERAL = re.compile(r'["\'](res://[^"\'\n]+)["\']')
FILE_LITERAL = re.compile(r'["\']([^"\'\n/]+\.(?:ogg|wav|png|ttf))["\']')
FORMAT_TOKEN = re.compile(r'%(?:\d+)?[sdf]')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def filters(value):
    return [part.strip() for part in value.split(',') if part.strip()]


def matches(path, patterns):
    # Godot's export glob treats a slash as a normal character. Thus native/*
    # excludes nested files, while environments/foo.png remains exact.
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def presets(root):
    # Godot strings can span physical lines (the Windows SSH script does),
    # which makes the whole file incompatible with Python's INI parser.
    configuration = (root / 'export_presets.cfg').read_text(encoding='utf-8')
    result = []
    for block in re.findall(r'(?ms)^\[preset\.\d+\]\n(.*?)(?=^\[|\Z)', configuration):
        def unquote(key):
            match = re.search(r'(?m)^' + re.escape(key) + r'=("[^\n]*")$', block)
            return json.loads(match.group(1)) if match else ''
        result.append({'name': unquote('name'), 'export_filter': unquote('export_filter'),
                       'include': filters(unquote('include_filter')),
                       'exclude': filters(unquote('exclude_filter'))})
    return result


def notice(path):
    name = path.name.lower()
    return (name in ('source.json', 'sources.json') or
            name.endswith(('.source.json', '_source.json', '_sources.json')) or
            (path.suffix.lower() in ('.txt', '.md') and ('license' in name or name == 'ofl.txt')))


def text_files(root):
    result = [root / 'project.godot']
    result.extend(path for path in root.iterdir() if path.is_file() and path.suffix in RESOURCE_TEXT)
    for directory in ('scripts', 'scenes', 'shaders', 'tests', 'assets'):
        result.extend(path for path in (root / directory).rglob('*')
                      if path.is_file() and path.suffix in RESOURCE_TEXT)
    return sorted(set(result))


def reference_inventory(root, files):
    """Return confirmed paths and unresolved dynamic prefixes separately."""
    required = defaultdict(list)
    dynamic = []
    existing = set(files)
    by_name = defaultdict(list)
    for path in existing:
        by_name[Path(path).name].append(path)

    def add(path, owner, kind):
        if path in existing:
            evidence = {'owner': owner, 'kind': kind}
            if evidence not in required[path]:
                required[path].append(evidence)

    for source in text_files(root):
        owner = source.relative_to(root).as_posix()
        contents = source.read_text(encoding='utf-8')
        for match in RESOURCE_LITERAL.finditer(contents):
            line_start = contents.rfind('\n', 0, match.start()) + 1
            prefix = contents[line_start:match.start()]
            # Export regressions explicitly assert that archive paths are
            # absent. Such an assertion is evidence for an exclusion, not a
            # runtime loader. A normal `if not exists` fallback stays a ref.
            if source.relative_to(root).parts[0] == 'tests' and re.search(
                    r'(?:_?check|assert)\(\s*not\s+(?:ResourceLoader\.exists|FileAccess\.file_exists)\(\s*$', prefix):
                continue
            path = match.group(1).removeprefix('res://')
            if path.endswith('/'):
                dynamic.append({'owner': owner, 'prefix': path, 'kind': 'open_directory'})
            elif FORMAT_TOKEN.search(path):
                pattern = FORMAT_TOKEN.sub('*', path)
                # The generic audio loader has a finite KINDS catalogue. Its
                # broad %s pattern would otherwise pretend archival convoy
                # recordings are runtime dependencies. Leave it unresolved.
                generic = path in ('assets/audio/%s_%02d.wav',)
                dynamic.append({'owner': owner, 'pattern': pattern,
                                'kind': 'catalogue_expansion_required' if generic else 'bounded_pattern'})
                if not generic:
                    for candidate in existing:
                        if matches(candidate, [pattern]):
                            add(candidate, owner, 'bounded_pattern')
            else:
                add(path, owner, 'literal')
        if source.suffix == '.gd':
            for match in FILE_LITERAL.finditer(contents):
                for path in by_name.get(match.group(1), []):
                    add(path, owner, 'filename_literal')

    # FileAccess dictionaries can contain complete ResourceLoader paths. Only
    # walk JSON actually referenced by runtime/embedded diagnostic code; an
    # old source provenance document is not a dependency manifest by itself.
    read_json = set()
    while True:
        pending = [path for path in required if path.endswith('.json') and path not in read_json]
        if not pending:
            break
        for path in pending:
            read_json.add(path)
            data = json.loads((root / path).read_text(encoding='utf-8'))
            strings = [data]
            while strings:
                item = strings.pop()
                if isinstance(item, dict):
                    strings.extend(item.values())
                elif isinstance(item, list):
                    strings.extend(item)
                elif isinstance(item, str) and item.startswith('res://'):
                    add(item.removeprefix('res://'), path, 'runtime_json')

    # Preserve complete current voice sets plus all authored depth plates and
    # masks; their runtime constructors use catalogued IDs rather than paths.
    for path in existing:
        if (path.startswith('assets/audio/story_voices_v2/') and path.endswith('.wav')
                and '/anchors/' not in path):
            add(path, 'scripts/story_dialogue_catalog.gd', 'current_voice_directory')
        if path.startswith(('assets/environments/layers/', 'assets/environments/surface_masks/')):
            if path.endswith(('.png', '/catalog.json')):
                add(path, 'scripts/parallax_catalog.gd / scripts/background_surface_catalog.gd', 'current_environment_directory')
    return dict(sorted(required.items())), sorted(dynamic, key=lambda item: (item['owner'], str(item)))


def audit(root):
    root = root.resolve()
    files = {path.relative_to(root).as_posix(): path for path in (root / 'assets').rglob('*')
             if path.is_file() and path.suffix not in ('.import', '.uid', '.tmp', '.pyc')}
    for path in text_files(root):
        files[path.relative_to(root).as_posix()] = path
    required, dynamic = reference_inventory(root, files)
    diagnostic_files = [path for path in files if path.startswith('tests/')]
    for path in diagnostic_files:
        required.setdefault(path, []).append({'owner': 'beta diagnostics policy', 'kind': 'retained_diagnostic'})
    configurations = presets(root)
    errors = []
    archive = ['assets/environments/' + name + '.png' for name in ARCHIVE_PANORAMAS]
    results = []
    for preset in configurations:
        excluded_required = [path for path in required if matches(path, preset['exclude'])]
        missing_archive_rules = [path for path in archive if not matches(path, preset['exclude'])]
        missing_source_rules = [path + '/' for path in NONRUNTIME_DIRS
                                if not matches(path + '/nested/probe.json', preset['exclude'])]
        if preset['export_filter'] != 'all_resources':
            errors.append(preset['name'] + ': all_resources is required for retained dynamic resources/diagnostics')
        if excluded_required:
            errors.append(preset['name'] + ': excluded confirmed dependencies: ' + ', '.join(excluded_required))
        if missing_archive_rules or missing_source_rules:
            errors.append(preset['name'] + ': missing reviewed archive exclusions: ' + ', '.join(missing_archive_rules + missing_source_rules))
        results.append({**preset, 'excluded_required': excluded_required,
                        'missing_archive_rules': missing_archive_rules,
                        'missing_source_rules': missing_source_rules,
                        'retained_diagnostics': len(diagnostic_files)})
    if configurations and any(item['exclude'] != configurations[0]['exclude'] for item in configurations[1:]):
        errors.append('Desktop/Beta export exclusions disagree')
    if len(configurations) != 3:
        errors.append('Expected Windows Desktop, Ubuntu Beta and Windows Beta presets')
    catalogue = json.loads((root / 'assets/environments/catalog.json').read_text())
    environments = {entry['id']: entry for entry in catalogue['environments']}
    archive_evidence = []
    for name in ARCHIVE_PANORAMAS:
        relative = 'assets/environments/' + name + '.png'
        replacement = environments.get(name, {}).get('path', '').removeprefix('res://')
        proven = relative not in required and replacement.startswith('assets/environments/v3/') and (root / replacement).is_file()
        if not proven:
            errors.append('Archive exclusion lacks current catalogue/reachability proof: ' + relative)
        archive_evidence.append({'path': relative, 'bytes': files[relative].stat().st_size if relative in files else 0,
                                 'replacement': replacement, 'proven': proven})
    provenance = [{'path': path, 'bytes': source.stat().st_size, 'sha256': digest(source)}
                  for path, source in sorted(files.items()) if path.startswith('assets/') and notice(source)]
    unclassified = [path for path in sorted(files) if path.startswith('assets/') and path not in required
                    and not notice(files[path]) and not matches(path, configurations[0]['exclude'] if configurations else [])]
    return {'success': not errors, 'errors': errors, 'presets': results,
            'confirmed_dependencies': required, 'dynamic_review': dynamic,
            'diagnostics_policy': 'Keep all embedded tests/scenes/shaders and their resource dependencies for beta diagnostics.',
            'archive_evidence': archive_evidence,
            'new_excluded_raw_bytes': sum(item['bytes'] for item in archive_evidence)
                                      + sum(path.stat().st_size for path in (root / 'native').rglob('*.json') if path.is_file()),
            'provenance_files': provenance,
            'provenance_packaging': 'tools/build_beta.py copies every listed notice byte-for-byte to licenses/asset-provenance/; current and archived originals remain on disk.',
            'unclassified_retained_assets': unclassified,
            'limitations': ['A missing literal reference is never proof that an asset or a dynamically called function is unused.',
                            'Open directory prefixes are not expanded into deletion candidates.',
                            'Raw source byte counts are not measured compressed PCK savings.',
                            'Run beta_asset_export_test.gd from an empty directory on each real exported platform for loading proof.'],
            'source_sha256': digest(root / 'export_presets.cfg')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/p1-beta-readiness-20261004/assets/audit.json')
    args = parser.parse_args()
    result = audit(args.root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'success': result['success'], 'errors': result['errors'],
                      'dependencies': len(result['confirmed_dependencies']),
                      'notices': len(result['provenance_files']),
                      'new_excluded_raw_bytes': result['new_excluded_raw_bytes']}))
    return 0 if result['success'] else 1


if __name__ == '__main__':
    sys.exit(main())
