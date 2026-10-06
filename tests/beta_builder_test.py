#!/usr/bin/env python3
"""Exercise beta packaging only in tiny disposable exports, plus real JSON PCKs."""
from contextlib import ExitStack, contextmanager
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'artifacts/archive-review/builder-verification.json'
spec = importlib.util.spec_from_file_location('beta_builder', ROOT / 'tools/build_beta.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
CHECKS = []
CASES = []
# JSON is a Resource in Godot 4.7.2. These FileAccess metadata paths must be
# present in the actual pack, whether exported by all_resources or filters.
RUNTIME_JSON = (
    'assets/releases/changelog.json',
    'assets/environments/background_surface_regions.json',
    'assets/environments/surface_masks/catalog.json',
    'assets/environments/panorama_edges.json',
    'assets/environments/v3/landmarks.json',
    'assets/enemies/machine_limbs_v1.source.json',
)


def check(condition, message):
    CHECKS.append({'passed': bool(condition), 'description': message})
    if not condition:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def snapshot(root):
    return {path.relative_to(root).as_posix(): path.read_bytes()
            for path in root.rglob('*') if path.is_file()}


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory(prefix='bunkercrew-builder-test-') as temporary:
        root = Path(temporary)
        version = 'test-beta'
        destination = root / 'beta' / version
        logs = root / 'artifacts' / ('beta-' + version)
        logs.mkdir(parents=True)
        (root / 'docs').mkdir()
        (root / 'docs/beta-coop-test.md').write_text('Disposable test documentation.\n')
        validation = {'success': True, 'binaries': {}, 'checks': [
            {'name': name, 'success': True} for name in (
                'smoke-linux', 'smoke-windows', 'medic-software-linux', 'medic-software-windows',
                'live-music-linux', 'live-music-windows', 'network_gameplay-linux-host-windows-guest',
                'network_gameplay-windows-host-linux-guest')]}
        for platform, (_, binary, _) in builder.TARGETS.items():
            target = destination / platform
            (target / 'licenses').mkdir(parents=True)
            (target / 'licenses/example.txt').write_text('Only this fixture; no actual game assets.\n')
            executable = ('fake ' + platform).encode()
            (target / binary).write_bytes(executable)
            library = 'native.so' if platform.startswith('ubuntu') else 'native.dll'
            (target / library).write_bytes(('fake native ' + platform).encode())
            info = {'version': version, 'platform': platform, 'network_protocol': 'fixture-protocol',
                    'world_revision': 4, 'source_sha256': 'a' * 64}
            (target / 'BUILD_INFO.json').write_text(json.dumps(info))
            (target / 'TEST_RESULTS.json').write_text('prior test record\n')
            (target / 'SHA256SUMS.txt').write_text('prior manifest\n')
            key = 'linux' if platform.startswith('ubuntu') else 'windows'
            validation['binaries'][key] = {'sha256': sha(executable), 'native_libraries': {
                library: {'sha256': builder.digest(target / library)}}}
        (logs / 'validation-report.json').write_text(json.dumps(validation))
        with ExitStack() as stack:
            for name, value in {'ROOT': root, 'DEST': destination, 'LOGS': logs, 'VERSION': version}.items():
                stack.enter_context(patch.object(builder, name, value))
            yield root, destination, logs, validation


def refused_unchanged(destination, message):
    before = snapshot(destination)
    refused = False
    try:
        builder.package()
    except SystemExit:
        refused = True
    check(refused, message + ': packaging refused')
    check(snapshot(destination) == before, message + ': every existing byte unchanged')


def archive_members(path):
    if path.suffix == '.zip':
        with zipfile.ZipFile(path) as archive:
            return {name.split('/', 1)[1]: archive.read(name) for name in archive.namelist()}
    with tarfile.open(path) as archive:
        return {entry.name.split('/', 1)[1]: archive.extractfile(entry).read()
                for entry in archive if entry.isfile()}


def packaging_cases():
    for marker in ('earlier-name.zip', 'earlier-name.tar.gz', 'SHA256SUMS.txt'):
        with fixture() as (_, destination, _, _):
            (destination / marker).write_bytes(b'existing historical bytes')
            refused_unchanged(destination, 'Preserve existing ' + marker)
        CASES.append('preserve:' + marker)
    for corrupted in ('executable', 'native', 'build_info', 'missing_build_info'):
        with fixture() as (_, destination, _, _):
            target = destination / 'windows-x86_64'
            if corrupted == 'executable':
                (target / 'Bunkercrew.exe').write_bytes(b'changed executable')
            elif corrupted == 'native':
                (target / 'native.dll').write_bytes(b'changed native library')
            elif corrupted == 'build_info':
                path = target / 'BUILD_INFO.json'
                info = json.loads(path.read_text())
                info['world_revision'] = 3
                path.write_text(json.dumps(info))
            else:
                (target / 'BUILD_INFO.json').unlink()
            refused_unchanged(destination, 'Second-target failure ' + corrupted)
        CASES.append('second-target:' + corrupted)
    with fixture() as (_, destination, _, _):
        before = snapshot(destination)
        original = builder._write_package_archive
        calls = []

        def fail_second(*args):
            calls.append(args[0])
            if len(calls) == 2:
                raise OSError('Fixture: failed second archive compression')
            original(*args)

        with patch.object(builder, '_write_package_archive', fail_second):
            failed = False
            try:
                builder.package()
            except OSError:
                failed = True
            check(failed and len(calls) == 2, 'Second archive compression failure injected')
        check(snapshot(destination) == before, 'Failed compression publishes no archives or rewritten metadata')
    CASES.append('compression rollback')
    with fixture() as (_, destination, _, _):
        before = snapshot(destination)
        original = os.link
        calls = []

        def fail_second_link(*args, **kwargs):
            calls.append(args[1])
            if len(calls) == 2:
                raise OSError('Fixture: failed second archive publication')
            return original(*args, **kwargs)

        with patch.object(builder.os, 'link', fail_second_link):
            failed = False
            try:
                builder.package()
            except OSError:
                failed = True
            check(failed and len(calls) == 2, 'Second archive publication failure injected')
        check(snapshot(destination) == before, 'Failed publication removes first archive and restores target metadata')
    CASES.append('publication rollback')
    with fixture() as (_, destination, _, validation):
        builder.package()
        top = (destination / 'SHA256SUMS.txt').read_text().splitlines()
        check(len(top) == 2, 'Successful package publishes exactly two top checksums')
        for line in top:
            checksum, filename = line.split('  ', 1)
            path = destination / filename
            check(builder.digest(path) == checksum, filename + ': top checksum matches real archive')
            members = archive_members(path)
            sums = dict((name, checksum) for checksum, name in
                        (line.split('  ', 1) for line in members['SHA256SUMS.txt'].decode().splitlines()))
            check(set(sums) == set(members) - {'SHA256SUMS.txt'}, filename + ': exact archived manifest membership')
            for relative, expected in sums.items():
                check(sha(members[relative]) == expected, filename + ': archive checksum ' + relative)
            check(json.loads(members['TEST_RESULTS.json']) == validation, filename + ': exact validated test record')
            target = destination / ('ubuntu-x86_64' if filename.endswith('.tar.gz') else 'windows-x86_64')
            check(members['SHA256SUMS.txt'] == (target / 'SHA256SUMS.txt').read_bytes(), filename + ': unpacked and archived manifest identical')
        refused_unchanged(destination, 'Repeated successful package')
    CASES.append('successful tar/zip and repeated package protection')


def export_consistency_cases():
    """Exercise real orchestration with only the external exporter substituted."""
    for mutation in ('none', 'preflight', 'first-export', 'added-file', 'removed-file',
                     'bus-layout', 'marker', 'final-copy', 'version'):
        with tempfile.TemporaryDirectory(prefix='bunkercrew-export-consistency-') as temporary:
            root = Path(temporary)
            (root / 'beta').mkdir()
            (root / 'scripts').mkdir()
            (root / 'project.godot').write_text('config/version="test-beta"\n')
            (root / 'export_presets.cfg').write_text('Disposable export presets.\n')
            (root / 'default_bus_layout.tres').write_text('original fixture audio bus\n')
            (root / 'scripts/network_protocol.gd').write_text(
                'const BUILD := "fixture-protocol"\nconst WORLD_REVISION := 4\n')
            source = root / 'scripts/changed.gd'
            source.write_text('original fixture source\n')
            destination = root / 'beta/test-beta'
            logs = root / 'logs'
            exports = []
            environments = []
            marker = root / 'ready'

            def fake_run(command, _log_name, env, *_args, **_kwargs):
                environments.append(env)
                if 'tests/content_pack_preflight.gd' in command:
                    report = next(argument.split('=', 1)[1] for argument in command
                                  if argument.startswith('--content-report='))
                    Path(report).write_text(json.dumps({'valid': True, 'content_fingerprint': 'f' * 64,
                                                       'packs': [{'id': 'fixture-base', 'version': '1.0.0'}]}))
                if mutation == 'preflight' and 'tests/core_impact_audio_test.gd' in command:
                    source.write_text('changed during preflight\n')
                if '--export-debug' in command:
                    binary = Path(command[-1])
                    binary.write_text(source.read_text())
                    exports.append(binary.read_text())
                    library = ('libbunkercrew_audio.linux.x86_64.so' if 'Ubuntu Beta' in command
                               else 'bunkercrew_audio.windows.x86_64.dll')
                    (binary.parent / library).write_text('fixture native library')
                    if len(exports) == 1:
                        if mutation == 'first-export':
                            source.write_text('changed between platform exports\n')
                        elif mutation == 'added-file':
                            (root / 'scripts/new.gd').write_text('new runtime source\n')
                        elif mutation == 'removed-file':
                            source.unlink()
                        elif mutation == 'bus-layout':
                            (root / 'default_bus_layout.tres').write_text('changed fixture audio bus\n')
                if '--script' in command and command[command.index('--script') + 1].endswith('licenses.gd'):
                    Path(command[-1]).write_text(json.dumps({'engine': 'fixture', 'licenses': {}, 'copyright': []}))

            def fake_copy(_source, target):
                target = Path(target)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('fixture notice')
                if mutation == 'final-copy':
                    source.write_text('changed during final package preparation\n')

            def fake_sleep(_seconds):
                marker.touch()
                source.write_text('changed while awaiting coordination\n')

            def fake_native(_godot, _env):
                if mutation == 'version':
                    (root / 'project.godot').write_text('config/version="changed-beta"\n')

            with ExitStack() as stack:
                for name, value in {'ROOT': root, 'DEST': destination, 'LOGS': logs, 'VERSION': 'test-beta',
                                    'PROTOCOL': 'fixture-protocol', 'WORLD_REVISION': 4}.items():
                    stack.enter_context(patch.object(builder, name, value))
                stack.enter_context(patch.object(builder, 'prepare_native', side_effect=fake_native))
                # Milestone validation has its own disposable-project suite;
                # this fixture isolates immutable export orchestration.
                stack.enter_context(patch.object(builder, 'require_release_notes'))
                stack.enter_context(patch.object(builder, 'run', side_effect=fake_run))
                stack.enter_context(patch.object(builder.shutil, 'copy2', side_effect=fake_copy))
                stack.enter_context(patch.object(builder, 'copy_asset_notices'))
                stack.enter_context(patch.object(builder.subprocess, 'check_output', return_value='fixture-engine\n'))
                if mutation == 'marker':
                    stack.enter_context(patch.object(builder.time, 'sleep', side_effect=fake_sleep))
                error = None
                try:
                    builder.export(marker if mutation == 'marker' else None)
                except RuntimeError as exception:
                    error = str(exception)
                if mutation == 'none':
                    infos = [json.loads((destination / platform / 'BUILD_INFO.json').read_text())
                             for platform in builder.TARGETS]
                    check(error is None and exports == ['original fixture source\n'] * 2,
                          'Unchanged source reaches both platform exporters')
                    check(all(info['source_sha256'] == builder.source_fingerprint(builder.source_manifest())
                              for info in infos), 'Both BUILD_INFO records identify the tested frozen inputs')
                    check(all(info['content_sha256'] == 'f' * 64 and
                              info['content_packs'] == [{'id': 'fixture-base', 'version': '1.0.0'}]
                              for info in infos), 'Both BUILD_INFO records retain the preflight content identity')
                else:
                    check(error is not None and ('Source changed' in error or 'version/protocol changed' in error),
                          mutation + ': source/version mutation aborts export')
                    expected_exports = (0 if mutation in ('preflight', 'version', 'marker') else
                                        2 if mutation == 'final-copy' else 1)
                    check(len(exports) == expected_exports, mutation + ': no later platform exported')
                    check(not list(destination.rglob('BUILD_INFO.json')),
                          mutation + ': inconsistent exports have no completed build identity')
                check(all(Path(env[key]).is_relative_to(Path(env['XDG_DATA_HOME']).parent)
                          for env in environments for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')),
                      mutation + ': build uses disposable data, config and cache directories')
            CASES.append('export consistency:' + mutation)


def provenance_case():
    expected = builder.asset_notice_files()
    with tempfile.TemporaryDirectory(prefix='bunkercrew-notices-test-') as temporary:
        notices = Path(temporary) / 'licenses'
        builder.copy_asset_notices(notices)
        destination = notices / 'asset-provenance'
        index = json.loads((destination / 'INDEX.json').read_text())
        names = {entry['path'] for entry in index['files']}
        check(names == {path.relative_to(ROOT).as_posix() for path in expected}, 'Provenance index includes all declared source and license files')
        for entry in index['files']:
            source = ROOT / entry['path']
            copied = destination / entry['path']
            check(source.read_bytes() == copied.read_bytes() and builder.digest(copied) == entry['sha256'],
                  'Exact packaged source/license: ' + entry['path'])
        for path in ('assets/vehicles/convoy_hull_v2.source.json', 'assets/expedition/convoy_runtime_v2.source.json',
                     'assets/enemies/aircraft_hulls_v1.source.json', 'assets/enemies/aircraft_hulls_v1.LICENSE.txt',
                     'assets/audio/convoy_v2_sources.json', 'assets/audio/aircraft_v1_sources.json',
                     'assets/audio/machinery_medical_v1_sources.json', 'assets/audio/medical_heal_01.LICENSE.txt',
                     'assets/audio/machinery_furnace_v1.LICENSE.txt'):
            check(path in names, 'New convoy/air/workshop/medical notices included: ' + path)
    CASES.append('complete provenance copies and hash index')


def run_godot(command, env, log):
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=120)
    log.write_text(result.stdout)
    check(result.returncode == 0 and not re.search(r'(?:SCRIPT ERROR:|ERROR:|WARNING:|Debugger Break)', result.stdout),
          'Clean minimal Godot run: ' + log.name)


def real_pack_case(godot):
    preset_text = (ROOT / 'export_presets.cfg').read_text()
    blocks = re.findall(r'(?ms)^\[preset\.(\d+)\]\n(.*?)(?=^\[preset\.\d+\]\n|\Z)', preset_text)
    check(len(blocks) == 3, 'All three actual export presets covered')
    with tempfile.TemporaryDirectory(prefix='bunkercrew-runtime-json-pack-') as temporary:
        root = Path(temporary)
        config = root / 'config'
        data = root / 'data'
        cache = root / 'cache'
        env = {**os.environ, 'XDG_CONFIG_HOME': str(config), 'XDG_DATA_HOME': str(data),
               'XDG_CACHE_HOME': str(cache)}
        original_data = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
        templates = original_data / 'godot/export_templates/4.7.2.stable'
        isolated_templates = data / 'godot/export_templates/4.7.2.stable'
        isolated_templates.parent.mkdir(parents=True)
        isolated_templates.symlink_to(templates, target_is_directory=True)
        project = root / 'minimal'
        project.mkdir()
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Bunkercrew raw JSON pack fixture"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        for relative in RUNTIME_JSON:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        paths = ['res://' + path for path in RUNTIME_JSON]
        (project / 'probe.gd').write_text('extends SceneTree\nfunc _initialize() -> void:\n\tvar result: Dictionary={}\n\tfor path: String in ' + json.dumps(paths) + ':\n\t\tresult[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"\n\tvar file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)\n\tfile.store_string(JSON.stringify(result))\n\tfile.close()\n\tquit()\n')
        logs = REPORT.parent / 'minimal-pack'
        logs.mkdir(parents=True, exist_ok=True)
        base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', str(project)]
        # Run exclusively from an empty directory: the source project's disk
        # files cannot satisfy a FileAccess probe of a missing pack member.
        runner = root / 'runner'
        runner.mkdir()
        probe_base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', str(runner)]
        for number, block in blocks:
            name = re.search(r'(?m)^name="([^"]+)"', block).group(1)
            preset = '[preset.0]\n' + re.sub(r'\[preset\.\d+\.options\]', '[preset.0.options]', block)
            (project / 'export_presets.cfg').write_text(preset)
            pack = root / ('included-' + number + '.pck')
            run_godot(base + ['--editor', '--recovery-mode', '--import', '--quit'], env, logs / f'import-{number}.log')
            run_godot(base + ['--editor', '--recovery-mode', '--export-pack', name, str(pack)], env, logs / f'export-{number}.log')
            output = root / ('included-' + number + '.json')
            run_godot(probe_base + ['--main-pack', str(pack), '--script', 'res://probe.gd', '--', str(output), '--no-profile-save', '--no-upnp'],
                      env, logs / f'probe-{number}.log')
            measurements = json.loads(output.read_text())
            for path in RUNTIME_JSON:
                check(measurements['res://' + path] == builder.digest(ROOT / path), name + ': actual PCK FileAccess bytes ' + path)
    CASES.append('real Godot all three unchanged preset packs, read without project disk files')


def main():
    global REPORT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=shutil.which('godot'))
    parser.add_argument('--skip-pack', action='store_true')
    parser.add_argument('--output', type=Path, default=REPORT, help='Verification JSON destination')
    args = parser.parse_args()
    REPORT = args.output.expanduser().resolve()
    error = None
    try:
        packaging_cases()
        export_consistency_cases()
        provenance_case()
        if not args.skip_pack:
            if not args.godot:
                raise RuntimeError('Godot is required for the real raw-JSON export proof.')
            real_pack_case(args.godot)
    except BaseException as exception:
        error = str(exception)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    report = {'success': error is None, 'checks': len(CHECKS), 'passed': sum(item['passed'] for item in CHECKS),
              'cases': CASES, 'error': error, 'results': CHECKS,
              'source_hashes': {str(path.relative_to(ROOT)): builder.digest(path) for path in (
                  ROOT / 'tools/build_beta.py', ROOT / 'export_presets.cfg', Path(__file__))},
              'scope': 'Only tiny disposable beta exports and isolated minimal Godot projects. Historical beta files and user profiles are never mutated.'}
    REPORT.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('success', 'checks', 'passed', 'error')}))
    if error:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
