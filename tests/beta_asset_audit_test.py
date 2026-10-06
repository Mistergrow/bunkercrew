#!/usr/bin/env python3
"""Export hygiene regressions, with actual packs built only in temporary projects."""
import argparse
from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('asset_audit', ROOT / 'tools/audit_beta_assets.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
CHECKS = []
REPORT_DIR = ROOT / 'artifacts/p1-beta-readiness-20261004/assets'


def check(ok, description):
    CHECKS.append({'passed': bool(ok), 'description': description})
    if not ok:
        raise AssertionError(description)


@contextmanager
def configuration_fixture(add_exclusion='', extra_script=None):
    """Link existing trees read-only in practice; mutate only the copied CFG."""
    with tempfile.TemporaryDirectory(prefix='bunkercrew-asset-audit-') as temporary:
        root = Path(temporary)
        for name in ('assets', 'scripts', 'scenes', 'shaders', 'tests', 'native'):
            (root / name).symlink_to(ROOT / name, target_is_directory=True)
        shutil.copy2(ROOT / 'project.godot', root / 'project.godot')
        cfg = (ROOT / 'export_presets.cfg').read_text()
        if add_exclusion:
            cfg = re.sub(r'(?m)^exclude_filter="([^"]+)"',
                         lambda match: 'exclude_filter="' + match.group(1) + ',' + add_exclusion + '"', cfg)
        (root / 'export_presets.cfg').write_text(cfg)
        if extra_script:
            (root / 'new_runtime_caller.gd').write_text(extra_script)
        yield root


def static_cases():
    before_notices = {str(path.relative_to(ROOT)): audit.digest(path)
                      for path in (ROOT / 'assets').rglob('*') if path.is_file() and audit.notice(path)}
    report = audit.audit(ROOT)
    check(report['success'], 'Actual source reference/catalogue audit passes')
    check(len(report['presets']) == 3, 'All three actual desktop export presets are checked')
    check(all(item['proven'] for item in report['archive_evidence']), 'Every earliest panorama has current v3 replacement and no loader')
    check(sum(item['bytes'] > 0 for item in report['archive_evidence']) == 9, 'Only nine actually existing earliest panoramas are excluded')
    required = report['confirmed_dependencies']
    for path in ('assets/environments/v3/ash_foundry.png', 'assets/environments/v2/ash_foundry.png',
                 'assets/environments/layers/ash_foundry_v1/sky.png',
                 'assets/environments/surface_masks/ash_foundry.png',
                 'assets/enemies/machine_limbs_v1.source.json',
                 'assets/audio/menu_rave_v1.ogg', 'assets/audio/music_rave_hoehenlicht_v2_combat.ogg',
                 'assets/audio/story_voices_v2/en/san_story_open.wav',
                 'assets/audio/live/libbunkercrew_audio.linux.x86_64.so',
                 'assets/audio/live/bunkercrew_audio.windows.x86_64.dll',
                 'tests/beta_asset_export_test.gd', 'tests/scene_cleanup.gd'):
        check(path in required, 'Confirmed dynamic/literal resource retained: ' + path)
    check(bool(report['unclassified_retained_assets']), 'Unknown assets remain review items, never deletion candidates')
    check(any(item.get('prefix') == 'assets/audio/' for item in report['dynamic_review']), 'Open audio directory prefix stays explicit')
    for exclusion, expected in (
            ('tests/*', 'tests/scene_cleanup.gd'),
            ('assets/environments/*.png', 'assets/environments/v3/ash_foundry.png'),
            ('assets/enemies/*.source.json', 'assets/enemies/machine_limbs_v1.source.json'),
            ('assets/audio/live/*', 'assets/audio/live/libbunkercrew_audio.linux.x86_64.so')):
        with configuration_fixture(exclusion) as root:
            result = audit.audit(root)
            check(not result['success'] and any(expected in error for error in result['errors']),
                  'Refuse destructive broad export exclusion: ' + exclusion)
    with configuration_fixture(extra_script='extends RefCounted\nconst OLD = preload("res://assets/environments/ash_foundry.png")\n') as root:
        result = audit.audit(root)
        check(not result['success'] and any('reachability proof' in error for error in result['errors']),
              'A new genuine archival loader invalidates the previously reviewed exclusion')
    with configuration_fixture(extra_script='extends RefCounted\nfunc fallback():\n\tif not ResourceLoader.exists("res://assets/environments/ash_foundry.png"): return\n') as root:
        check(not audit.audit(root)['success'], 'Existence guard in real code still counts as a dependency')
    check(audit.matches('native/api/nested/data.json', ['native/*']), 'Godot slash-crossing exclusion glob covers nested author data')
    check(not audit.matches('assets/environments/v3/ash_foundry.png', ['assets/environments/ash_foundry.png']),
          'Exact earliest panorama exclusion never excludes current image')
    after_notices = {str(path.relative_to(ROOT)): audit.digest(path)
                     for path in (ROOT / 'assets').rglob('*') if path.is_file() and audit.notice(path)}
    check(before_notices == after_notices, 'All current and archived source/license bytes remain unchanged')


def run_godot(command, env, log):
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=120)
    log.write_text(result.stdout)
    check(result.returncode == 0 and not re.search(r'(?:SCRIPT ERROR:|ERROR:|WARNING:|Debugger Break)', result.stdout),
          'Clean real Godot step: ' + log.name)


def pack_cases(godot):
    raw = ('assets/environments/catalog.json', 'assets/environments/background_surface_regions.json',
           'assets/environments/surface_masks/catalog.json', 'assets/environments/panorama_edges.json',
           'assets/environments/v3/landmarks.json', 'assets/enemies/machine_limbs_v1.source.json',
           'assets/environments/life/vegetation_v1.source.json', 'locales/de.json', 'locales/en.json')
    loadable = ('assets/environments/v3/ash_foundry.png', 'assets/environments/v2/ash_foundry.png',
                'assets/environments/layers/ash_foundry_v1/sky.png', 'assets/audio/menu_rave_v1.ogg',
                'assets/audio/music_rave_hoehenlicht_v2_combat.ogg', 'assets/audio/story_voices_v2/en/san_story_open.wav')
    absent = ('assets/environments/ash_foundry.png', 'assets/audio/story_voices/san_story_open.wav',
              'assets/audio/story_voices_v2/anchors/not_a_runtime_voice.wav',
              'native/bunkercrew_audio/api/extension_api.json', 'tools/source_only.gd',
              'server/source_only.json', 'reference/source_only.json', 'artifacts/source_only.json', 'beta/source_only.json')
    blocks = re.findall(r'(?ms)^\[preset\.(\d+)\]\n(.*?)(?=^\[preset\.\d+\]\n|\Z)',
                        (ROOT / 'export_presets.cfg').read_text())
    with tempfile.TemporaryDirectory(prefix='bunkercrew-reviewed-asset-packs-') as temporary:
        directory = Path(temporary)
        data = directory / 'data'
        env = {**os.environ, 'XDG_CONFIG_HOME': str(directory / 'config'),
               'XDG_DATA_HOME': str(data), 'XDG_CACHE_HOME': str(directory / 'cache')}
        templates = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'godot/export_templates/4.7.2.stable'
        isolated = data / 'godot/export_templates/4.7.2.stable'
        isolated.parent.mkdir(parents=True)
        isolated.symlink_to(templates, target_is_directory=True)
        project = directory / 'fixture'
        project.mkdir()
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Disposable asset export regression"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        for relative in raw + loadable + absent[:2] + (absent[3],):
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        target = project / absent[2]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / absent[1], target)
        for relative in absent[4:]:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('extends RefCounted\n' if target.suffix == '.gd' else '{"author_fixture":true}\n')
        diagnostic = project / 'tests/embedded_diagnostic.gd'
        diagnostic.parent.mkdir()
        diagnostic.write_text('extends RefCounted\nfunc verify() -> bool:\n\treturn JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/machine_limbs_v1.source.json")) is Dictionary\n')
        probe = '''extends SceneTree
func _initialize() -> void:
\tvar report: Dictionary={"raw":{},"loadable":{},"absent":{},"diagnostic":false}
\tfor path: String in RAW:
\t\treport.raw[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
\tfor path: String in LOADABLE:
\t\treport.loadable[path]=ResourceLoader.exists(path) and load(path)!=null
\tfor path: String in ABSENT:
\t\treport.absent[path]=not FileAccess.file_exists(path) and not ResourceLoader.exists(path)
\tvar diagnostic: Resource=load("res://tests/embedded_diagnostic.gd")
\treport.diagnostic=diagnostic!=null and bool(diagnostic.new().verify())
\tvar output:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
\toutput.store_string(JSON.stringify(report))
\toutput.close()
\tquit()
'''
        for name, paths in (('RAW', raw), ('LOADABLE', loadable), ('ABSENT', absent)):
            probe = probe.replace(' in ' + name + ':', ' in ' + json.dumps(['res://' + path for path in paths]) + ':')
        (project / 'probe.gd').write_text(probe)
        runner = directory / 'empty-runner'
        runner.mkdir()
        logs = REPORT_DIR / 'minimal-packs'
        logs.mkdir(parents=True, exist_ok=True)
        base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', str(project)]
        for number, block in blocks:
            name = re.search(r'(?m)^name="([^"]+)"', block).group(1)
            preset = '[preset.0]\n' + re.sub(r'\[preset\.\d+\.options\]', '[preset.0.options]', block)
            (project / 'export_presets.cfg').write_text(preset)
            pack = directory / ('verified-' + number + '.pck')
            run_godot(base + ['--editor', '--recovery-mode', '--import', '--quit'], env, logs / f'import-{number}.log')
            run_godot(base + ['--editor', '--recovery-mode', '--export-pack', name, str(pack)], env, logs / f'export-{number}.log')
            output = directory / ('probe-' + number + '.json')
            run_godot([godot, '--headless', '--audio-driver', 'Dummy', '--path', str(runner),
                       '--main-pack', str(pack), '--script', 'res://probe.gd', '--', str(output),
                       '--no-profile-save', '--no-upnp'], env, logs / f'probe-{number}.log')
            result = json.loads(output.read_text())
            for relative in raw:
                check(result['raw']['res://' + relative] == audit.digest(ROOT / relative), name + ': exact packed FileAccess JSON ' + relative)
            for relative in loadable:
                check(result['loadable']['res://' + relative], name + ': actual resource loads from pack ' + relative)
            for relative in absent:
                check(result['absent']['res://' + relative], name + ': archive/build file absent from actual pack ' + relative)
            check(result['diagnostic'], name + ': embedded compiled diagnostic runs with its actual metadata')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-pack', action='store_true')
    parser.add_argument('--godot', default=shutil.which('godot'))
    args = parser.parse_args()
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    error = None
    try:
        static_cases()
        if not args.skip_pack:
            if not args.godot:
                raise RuntimeError('Godot 4.7.2 is required for actual pack proof')
            pack_cases(args.godot)
    except BaseException as exception:
        error = str(exception)
    report = {'success': error is None, 'checks': len(CHECKS), 'passed': sum(item['passed'] for item in CHECKS),
              'error': error, 'results': CHECKS,
              'scope': 'Read-only source audit plus actual three-preset exports in temporary minimal projects, probed from an empty directory. Not the final complete game exports.'}
    (REPORT_DIR / 'audit-regression.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('success', 'checks', 'passed', 'error')}))
    return 1 if error else 0


if __name__ == '__main__':
    raise SystemExit(main())
