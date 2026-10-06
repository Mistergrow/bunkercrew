#!/usr/bin/env python3
"""Export matching desktop betas; archive only after validating the executables."""
import argparse
import hashlib
import io
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.search(r'config/version="([^"]+)"', (ROOT / 'project.godot').read_text()).group(1)
PROTOCOL = re.search(r'const BUILD := "([^"]+)"', (ROOT / 'scripts/network_protocol.gd').read_text()).group(1)
WORLD_REVISION = int(re.search(r'const WORLD_REVISION := (\d+)', (ROOT / 'scripts/network_protocol.gd').read_text()).group(1))
DEST = ROOT / 'beta' / VERSION
LOGS = ROOT / 'artifacts' / f'beta-{VERSION}'
TARGETS = {
    'ubuntu-x86_64': ('Ubuntu Beta', 'Bunkercrew.x86_64', 'Ubuntu-x86_64'),
    'windows-x86_64': ('Windows Beta', 'Bunkercrew.exe', 'Windows-x86_64'),
}


def asset_notice_files():
    """Retain provenance/terms for current and archived project assets."""
    result = []
    for path in sorted((ROOT / 'assets').rglob('*')):
        if not path.is_file():
            continue
        name = path.name.lower()
        source = (name in ('source.json', 'sources.json') or
                  name.endswith(('.source.json', '_source.json', '_sources.json')))
        license_file = (path.suffix.lower() in ('.txt', '.md') and
                        ('license' in name or name == 'ofl.txt'))
        if source or license_file:
            result.append(path)
    return result


def copy_asset_notices(notices):
    destination = notices / 'asset-provenance'
    entries = []
    for path in asset_notice_files():
        relative = path.relative_to(ROOT)
        copied = destination / relative
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, copied)
        entries.append({'path': relative.as_posix(), 'bytes': path.stat().st_size,
                        'sha256': digest(copied)})
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'INDEX.json').write_text(json.dumps({
        'description': 'Asset provenance and license notices, preserving repository paths. '
                       'Includes notices for archived source assets; inclusion here does not '
                       'mean their source recording or bitmap is shipped in the game pack.',
        'files': entries,
    }, indent=2) + '\n')


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def source_manifest():
    """Freeze runtime, shipped documentation and build inputs after import."""
    files = [ROOT / 'project.godot', ROOT / 'export_presets.cfg']
    if (ROOT / 'CHANGELOG.md').is_file(): files.append(ROOT / 'CHANGELOG.md')
    for pattern in ('*.tres', '*.tscn', '*.gd', '*.gdshader', '*.gdextension'):
        files.extend(path for path in ROOT.glob(pattern) if path.is_file())
    for directory in ('scripts', 'scenes', 'shaders', 'assets', 'locales', 'tests',
                      'docs', 'server', 'tools', 'native/bunkercrew_audio/src',
                      'native/bunkercrew_audio/third_party/tessel'):
        files.extend(path for path in (ROOT / directory).rglob('*') if path.is_file()
                     and not any(part in ('__pycache__', '.venv') for part in path.parts)
                     and path.suffix not in ('.pyc', '.tmp'))
    for relative in ('native/bunkercrew_audio/CMakeLists.txt',
                     'native/bunkercrew_audio/mingw-toolchain.cmake',
                     'native/bunkercrew_audio/build_profile.json',
                     'native/bunkercrew_audio/api/extension_api.json',
                     'native/bunkercrew_audio/third_party/godot-cpp/SOURCE.json',
                     'native/bunkercrew_audio/third_party/godot-cpp/LICENSE.md',
                     'native/bunkercrew_audio/third_party/mingw-w64/NOTICE',
                     'native/bunkercrew_audio/third_party/mingw-w64/GCC-NOTICE',
                     'native/bunkercrew_audio/third_party/mingw-w64/SOURCE.json'):
        path = ROOT / relative
        if path.is_file():
            files.append(path)
    return {path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(files)}


def source_fingerprint(manifest):
    checksum = hashlib.sha256()
    for relative, sha256 in sorted(manifest.items()):
        checksum.update((relative + '\0' + sha256 + '\n').encode())
    return checksum.hexdigest()


def require_unchanged_source(expected):
    current = source_manifest()
    changed = sorted(relative for relative in expected.keys() | current.keys()
                     if expected.get(relative) != current.get(relative))
    if changed:
        raise RuntimeError('Source changed during beta preflight/export; discard the incomplete '
                           'exports and rebuild the frozen version. Changed files: ' + ', '.join(changed[:12]))


def require_current_build_identity():
    project = (ROOT / 'project.godot').read_text()
    protocol = (ROOT / 'scripts/network_protocol.gd').read_text()
    actual = (re.search(r'config/version="([^"]+)"', project).group(1),
              re.search(r'const BUILD := "([^"]+)"', protocol).group(1),
              int(re.search(r'const WORLD_REVISION := (\d+)', protocol).group(1)))
    if actual != (VERSION, PROTOCOL, WORLD_REVISION):
        raise RuntimeError('Beta version/protocol changed during preparation; restart the build.')


def require_release_notes():
    spec = importlib.util.spec_from_file_location('bunkercrew_versioning', Path(__file__).with_name('bump_version.py'))
    versioning = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(versioning)
    try:
        versioning.validate_release(ROOT)
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise RuntimeError('Version/changelog preflight failed: ' + str(error)) from error


def run(command, log_name, env, cwd=ROOT, timeout=300):
    log_path = LOGS / log_name
    with log_path.open('w') as log:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=timeout)
    text = log_path.read_text(errors='replace')
    if result.returncode or re.search(r'^(?:SCRIPT ERROR:|ERROR:|WARNING:)', text, re.M):
        raise RuntimeError(f'{log_path}:\n{text[-8000:]}')
    print(f'PASS {log_name}', flush=True)


def native_inputs_hash(godot):
    files = [ROOT / 'tools/build_live_music.py', ROOT / 'tests/live_music_export_themes.gd',
             ROOT / 'scripts/music_theme_catalog.gd', ROOT / 'scripts/music_genre_catalog.gd',
             ROOT / 'assets/audio/live/normalization.json',
             ROOT / 'native/bunkercrew_audio/CMakeLists.txt',
             ROOT / 'native/bunkercrew_audio/mingw-toolchain.cmake',
             ROOT / 'native/bunkercrew_audio/api/extension_api.json',
             ROOT / 'native/bunkercrew_audio/third_party/godot-cpp/SOURCE.json']
    for directory in ('native/bunkercrew_audio/src', 'native/bunkercrew_audio/third_party/tessel'):
        files.extend(path for path in (ROOT / directory).rglob('*') if path.is_file())
    checksum = hashlib.sha256(subprocess.check_output([godot, '--version']))
    for path in sorted(files):
        checksum.update((str(path.relative_to(ROOT)) + '\0' + digest(path) + '\n').encode())
    return checksum.hexdigest()


def prepare_native(godot, env):
    # Prepare this expensive prerequisite separately while gameplay is reviewed.
    # Reuse only identical verified sources, binaries and verification output.
    stamp = LOGS / 'native-prerequisites.json'
    outputs = [ROOT / 'assets/audio/live/libbunkercrew_audio.linux.x86_64.so',
               ROOT / 'assets/audio/live/bunkercrew_audio.windows.x86_64.dll',
               ROOT / 'assets/audio/live/native.source.json',
               ROOT / 'artifacts/live-music/native-verification.json']
    source_hash = native_inputs_hash(godot)
    if stamp.is_file():
        prepared = json.loads(stamp.read_text())
        if prepared.get('source_sha256') == source_hash and all(
                path.is_file() and prepared.get('outputs', {}).get(str(path.relative_to(ROOT))) == digest(path)
                for path in outputs):
            print('PASS reused verified native prerequisites for unchanged sources', flush=True)
            return
    run([sys.executable, str(ROOT / 'tools/build_live_music.py'), '--platform', 'all',
         '--verify', '--endurance-hours', '2', '--godot', godot],
        'live-music-build.log', env, timeout=1800)
    verification = json.loads(outputs[-1].read_text())
    if not verification.get('endurance', {}).get('full_endurance'):
        raise RuntimeError('Native prerequisite must include the complete endurance verification.')
    stamp.write_text(json.dumps({'source_sha256': native_inputs_hash(godot),
                                 'outputs': {str(path.relative_to(ROOT)): digest(path) for path in outputs},
                                 'offline_endurance_hours': 2}, indent=2) + '\n')


def native_only():
    godot = os.environ.get('GODOT') or shutil.which('godot')
    if not godot:
        raise SystemExit('Godot is required to prepare native audio.')
    LOGS.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='bunkercrew-beta-native-') as temporary:
        env = {**os.environ, 'XDG_DATA_HOME': str(Path(temporary) / 'data'),
               'XDG_CONFIG_HOME': str(Path(temporary) / 'config'),
               'XDG_CACHE_HOME': str(Path(temporary) / 'cache')}
        prepare_native(godot, env)
    print('Native prerequisites ready; no desktop export has started.', flush=True)


def export(wait_for_export_file=None):
    if DEST.exists():
        raise SystemExit(f'Build directory already exists: {DEST}; preserve it or choose a new version.')
    godot = os.environ.get('GODOT') or shutil.which('godot')
    if not godot:
        raise SystemExit('Godot is required to export.')
    LOGS.mkdir(parents=True, exist_ok=True)
    (ROOT / 'beta/.gdignore').touch()
    with tempfile.TemporaryDirectory(prefix='lastshift-beta-build-') as temporary:
        env = {**os.environ, 'XDG_DATA_HOME': str(Path(temporary) / 'data'),
               'XDG_CONFIG_HOME': str(Path(temporary) / 'config'),
               'XDG_CACHE_HOME': str(Path(temporary) / 'cache')}
        # Reuse installed templates while keeping editor data in a temporary directory.
        templates = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'godot/export_templates/4.7.2.stable'
        isolated_templates = Path(env['XDG_DATA_HOME']) / 'godot/export_templates/4.7.2.stable'
        isolated_templates.parent.mkdir(parents=True, exist_ok=True)
        isolated_templates.symlink_to(templates, target_is_directory=True)
        base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT)]
        prepare_native(godot, env)
        run(base + ['--editor', '--recovery-mode', '--import', '--quit'], 'import.log', env)
        require_current_build_identity()
        require_release_notes()
        frozen_source = source_manifest()
        content_report = Path(temporary) / 'content-preflight.json'
        run(base + ['--script', 'tests/content_pack_preflight.gd', '--', '--no-profile-save', '--no-upnp',
                    f'--content-report={content_report}'], 'content-preflight.log', env)
        content = json.loads(content_report.read_text())
        if not content.get('valid'):
            raise RuntimeError('Enabled content packs failed validation.')
        for test in ('music_beat_clock', 'music_genre', 'live_music', 'live_music_native',
                     'live_music_integration', 'live_music_native_profiles', 'audio_settings', 'options_ui',
                     'rhythm_visual', 'rhythm_dance', 'rhythm_dashboard', 'station_shader_lifetime',
                     'music_calibration_ui', 'medic_dance', 'medic_software',
                     'medic_logistics_expansion', 'medic_campaign_cargo', 'core_impact_audio'):
            run(base + ['--script', 'tests/' + test + '_test.gd', '--', '--no-profile-save', '--no-upnp'],
                test + '.log', env)
        require_unchanged_source(frozen_source)
        if wait_for_export_file is not None:
            print(f'READY desktop exports; awaiting coordination marker {wait_for_export_file}', flush=True)
            deadline = time.monotonic() + 600
            while not wait_for_export_file.is_file():
                if time.monotonic() >= deadline:
                    raise RuntimeError('Desktop export coordination timed out; no exports started.')
                time.sleep(0.1)
        require_unchanged_source(frozen_source)
        DEST.mkdir(parents=True)
        engine = subprocess.check_output([godot, '--version'], text=True).strip()
        for platform, (preset, binary, _) in TARGETS.items():
            target = DEST / platform
            target.mkdir()
            run(base + ['--editor', '--recovery-mode', '--export-debug', preset, str(target / binary)],
                f'export-{platform}.log', env)
            require_unchanged_source(frozen_source)
            if not (target / binary).is_file():
                raise RuntimeError(f'Missing export: {target / binary}')
        license_script = Path(temporary) / 'licenses.gd'
        license_output = Path(temporary) / 'godot-licenses.json'
        license_script.write_text('''extends SceneTree
func _initialize() -> void:
\tvar file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
\tfile.store_string(JSON.stringify({"engine":Engine.get_license_text(),"licenses":Engine.get_license_info(),"copyright":Engine.get_copyright_info()},"  "))
\tfile.close()
\tquit()
''')
        run([godot, '--headless', '--audio-driver', 'Dummy', '--path', temporary,
             '--script', str(license_script), '--', str(license_output)], 'licenses.log', env, temporary)
        licenses = json.loads(license_output.read_text())
        source_sha256 = source_fingerprint(frozen_source)
        pending_builds = []
        for platform in TARGETS:
            target = DEST / platform
            shutil.copy2(ROOT / 'docs/beta-coop-test.md', target / 'README.md')
            shutil.copy2(ROOT / 'CHANGELOG.md', target / 'CHANGELOG.md')
            (target / 'docs').mkdir()
            shutil.copy2(ROOT / 'docs/network-server.md', target / 'docs/network-server.md')
            (target / 'server').mkdir()
            for filename in ('relay.py', 'social.py', 'requirements.txt'):
                shutil.copy2(ROOT / 'server' / filename, target / 'server' / filename)
            notices = target / 'licenses'
            notices.mkdir()
            (notices / 'Godot.txt').write_text(licenses['engine'])
            (notices / 'Godot-third-party.json').write_text(json.dumps(licenses, indent=2, ensure_ascii=False))
            for source_path, name in (
                ('assets/font-license.txt', 'font.txt'),
                ('assets/fonts/barlow/OFL.txt', 'Barlow-OFL.txt'),
                ('assets/audio/weapon_sources.json', 'weapon-audio-sources.json'),
                ('assets/audio/story_voices/README.md', 'generated-voices.md'),
                ('assets/audio/story_voices/MODEL_LICENSE.txt', 'voice-model-Apache-2.0.txt'),
                ('native/bunkercrew_audio/third_party/tessel/LICENSE', 'Audiote-Tessel-Bunkercrew-only.txt'),
                ('native/bunkercrew_audio/third_party/godot-cpp/LICENSE.md', 'godot-cpp-MIT.md'),
                ('assets/audio/live/native.source.json', 'live-music-source.json'),
                ('native/bunkercrew_audio/third_party/mingw-w64/NOTICE', 'MinGW-runtime.txt'),
                ('native/bunkercrew_audio/third_party/mingw-w64/GCC-NOTICE', 'GCC-runtime-exception.txt'),
                ('native/bunkercrew_audio/third_party/mingw-w64/SOURCE.json', 'MinGW-runtime-source.json'),
            ):
                shutil.copy2(ROOT / source_path, notices / name)
            copy_asset_notices(notices)
            core_audio = notices / 'core-impact'
            core_audio.mkdir()
            for path in sorted((ROOT / 'assets/audio').glob('impact_core_*.source.json')):
                shutil.copy2(path, core_audio / path.name)
                license_path = path.with_suffix('').with_suffix('.LICENSE.txt')
                shutil.copy2(license_path, core_audio / license_path.name)
            generated_art = notices / 'generated-art'
            generated_art.mkdir()
            shutil.copy2(ROOT / 'assets/environments/distant_horizon.source.json',
                         generated_art / 'distant_horizon.source.json')
            (generated_art / 'README.txt').write_text(
                'The distant_horizon.png landscape atlas was generated for Bunkercrew '
                'using the built-in OpenAI image_gen tool. Its full prompt, generation date, '
                'original output path and atlas regions are recorded in distant_horizon.source.json. '
                'The image is embedded in the game pack. New sky and underground rendering '
                'uses existing project textures and Godot shaders; it introduces no new '
                'generated sky or earth images.\n')
            build = {'version': VERSION, 'network_protocol': PROTOCOL, 'world_revision': WORLD_REVISION, 'platform': platform,
                     'build_type': 'debug export for beta diagnostics',
                     'engine': engine, 'renderer': 'gl_compatibility', 'source_sha256': source_sha256,
                     'content_sha256': content['content_fingerprint'],
                     'content_packs': [{'id': pack['id'], 'version': pack['version']} for pack in content['packs']],
                     'beta_diagnostics': 'Embedded regression scripts; not executed during normal gameplay.'}
            library_name = ('libbunkercrew_audio.linux.x86_64.so' if platform.startswith('ubuntu')
                            else 'bunkercrew_audio.windows.x86_64.dll')
            libraries = list(target.rglob(library_name))
            if len(libraries) != 1:
                raise RuntimeError(f'Missing or ambiguous exported live-music library: {library_name}')
            library = libraries[0]
            build['live_music'] = {'backend': 'Tessel native GDExtension', 'library': str(library.relative_to(target)),
                                   'sha256': digest(library), 'offline_endurance_hours': 2}
            shutil.copy2(ROOT / 'artifacts/live-music/native-verification.json',
                         target / 'LIVE_MUSIC_TEST_RESULTS.json')
            pending_builds.append((target / 'BUILD_INFO.json', build))
        launcher = DEST / 'ubuntu-x86_64/Start.sh'
        launcher.write_text('#!/bin/sh\nset -eu\ncd -- "$(dirname -- "$0")"\nexec ./Bunkercrew.x86_64 "$@"\n')
        launcher.chmod(0o755)
        (DEST / 'ubuntu-x86_64/Bunkercrew.x86_64').chmod(0o755)
        require_unchanged_source(frozen_source)
        for path, build in pending_builds:
            path.write_text(json.dumps(build, indent=2) + '\n')
    print(f'Exports ready for tools/validate_beta.py: {DEST}', flush=True)


def _package_preflight(validation):
    # Never replace historical packages, including packages from an earlier
    # project name. Do this before touching any target's TEST_RESULTS/manifest.
    if (DEST / 'SHA256SUMS.txt').exists() or any(DEST.glob('*.tar.gz')) or any(DEST.glob('*.zip')):
        raise SystemExit(f'Archives already exist in {DEST}; preserve them or choose a new version.')
    builds = []
    for platform, (_, binary, _) in TARGETS.items():
        target = DEST / platform
        if not (target / binary).is_file():
            raise SystemExit(f'Missing exported executable for {platform}.')
        validation_platform = 'linux' if platform.startswith('ubuntu') else 'windows'
        verified = validation.get('binaries', {}).get(validation_platform, {})
        if verified.get('sha256') != digest(target / binary):
            raise SystemExit(f'Validated executable does not match {platform}.')
        for relative, expected in verified.get('native_libraries', {}).items():
            path = target / relative
            if not path.is_file() or digest(path) != expected['sha256']:
                raise SystemExit(f'Validated native library does not match {platform}: {relative}')
        info = target / 'BUILD_INFO.json'
        if not info.is_file():
            raise SystemExit(f'Missing BUILD_INFO.json for {platform}.')
        build = json.loads(info.read_text())
        if build.get('version') != VERSION or build.get('platform') != platform:
            raise SystemExit(f'BUILD_INFO does not match {platform}/{VERSION}.')
        builds.append(build)
    for key in ('version', 'network_protocol', 'world_revision', 'source_sha256', 'content_sha256', 'content_packs'):
        if builds[0].get(key) != builds[1].get(key):
            raise SystemExit(f'Exported platforms disagree on {key}.')


def _write_package_archive(target, name, archive, extra):
    files = sorted(path for path in target.rglob('*') if path.is_file()
                   and path.relative_to(target).as_posix() not in extra)
    if archive.name.endswith('.tar.gz'):
        with tarfile.open(archive, 'w:gz', compresslevel=6) as output:
            for path in files:
                output.add(path, arcname=f'{name}/{path.relative_to(target).as_posix()}')
            for relative, data in extra.items():
                info = tarfile.TarInfo(f'{name}/{relative}')
                info.size = len(data)
                info.mode = 0o644
                output.addfile(info, io.BytesIO(data))
    else:
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as output:
            for path in files:
                output.write(path, Path(name) / path.relative_to(target))
            for relative, data in extra.items():
                output.writestr(f'{name}/{relative}', data)


def _commit_package_files(pending, exclusive):
    """Publish prepared files; roll back this attempt if publication fails."""
    published = []
    backups = {}
    try:
        for source, target in pending:
            if target in exclusive:
                # Link is an exclusive, atomic creation. A concurrent package
                # cannot replace an archive that appeared after preflight.
                os.link(source, target)
            else:
                if target.exists():
                    backup = source.with_name(source.name + '.rollback')
                    shutil.copy2(target, backup)
                    backups[target] = backup
                os.replace(source, target)
            published.append(target)
    except BaseException:
        for target in reversed(published):
            if target in backups:
                os.replace(backups[target], target)
            else:
                target.unlink(missing_ok=True)
        raise


def package():
    report = LOGS / 'validation-report.json'
    if not report.is_file():
        raise SystemExit('Run tools/validate_beta.py before packaging.')
    validation = json.loads(report.read_text())
    if not validation.get('success'):
        raise SystemExit('Beta validation has not passed; inspect validation-report.json.')
    required_checks = {'smoke-linux', 'smoke-windows',
                       'medic-software-linux', 'medic-software-windows',
                       'live-music-linux', 'live-music-windows',
                       'network_gameplay-linux-host-windows-guest',
                       'network_gameplay-windows-host-linux-guest'}
    passed_checks = {check['name'] for check in validation.get('checks', []) if check.get('success')}
    if not required_checks.issubset(passed_checks):
        raise SystemExit('Both package checks and both cross-platform ENet host directions must pass.')
    _package_preflight(validation)
    archives = []
    with tempfile.TemporaryDirectory(prefix='.package-', dir=DEST) as temporary:
        stage = Path(temporary)
        pending = []
        for platform, (_, _, label) in TARGETS.items():
            target = DEST / platform
            result = (json.dumps(validation, indent=2) + '\n').encode()
            members = {p.relative_to(target).as_posix(): digest(p) for p in sorted(target.rglob('*'))
                       if p.is_file() and p.relative_to(target).as_posix() not in ('TEST_RESULTS.json', 'SHA256SUMS.txt')}
            members['TEST_RESULTS.json'] = hashlib.sha256(result).hexdigest()
            checksum = ''.join(f'{sha}  {name}\n' for name, sha in sorted(members.items())).encode()
            extra = {'TEST_RESULTS.json': result, 'SHA256SUMS.txt': checksum}
            name = f'Bunkercrew-{VERSION}-{label}'
            filename = name + ('.tar.gz' if platform.startswith('ubuntu') else '.zip')
            staged_archive = stage / filename
            _write_package_archive(target, name, staged_archive, extra)
            archive = DEST / filename
            pending.append((staged_archive, archive))
            archives.append(archive)
            for relative, data in extra.items():
                prepared = stage / platform / relative
                prepared.parent.mkdir(parents=True, exist_ok=True)
                prepared.write_bytes(data)
                pending.append((prepared, target / relative))
        top = stage / 'SHA256SUMS.txt'
        top.write_text(''.join(f'{digest(stage / archive.name)}  {archive.name}\n' for archive in archives))
        readme = stage / 'README.md'
        shutil.copy2(ROOT / 'docs/beta-coop-test.md', readme)
        pending.extend(((top, DEST / top.name), (readme, DEST / readme.name)))
        # Both archives and all metadata are ready before any target is changed.
        _commit_package_files(pending, set(archives) | {DEST / 'SHA256SUMS.txt'})
    for archive in archives:
        print(f'PACKAGED {archive.name} ({archive.stat().st_size / 1024**2:.1f} MiB)', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--package', action='store_true', help='Archive validated exports without rebuilding.')
    mode.add_argument('--prepare-native', action='store_true', help='Build and verify native audio without starting desktop exports.')
    parser.add_argument('--wait-for-export-file', type=Path, help='Wait after source preflight until this coordination file exists before writing desktop exports.')
    args = parser.parse_args()
    if args.wait_for_export_file is not None and (args.package or args.prepare_native):
        parser.error('--wait-for-export-file requires the desktop export mode')
    package() if args.package else native_only() if args.prepare_native else export(args.wait_for_export_file)
