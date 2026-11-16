"""Copy the scripts a production GDScript really depends on into a fixture project.

Disposable display fixtures run one production script in an otherwise empty
project. A hand-written list of the files it needs goes stale as soon as one of
them gains a new preload. This derives the list from the sources instead:

* every literal ``"res://….gd"`` (preload, load, path-based ``extends``), and
* every reference to a ``class_name`` global declared under ``scripts/``,

followed transitively. Dependencies keep their ``res://`` paths. Referenced
globals are also written to the fixture's global class cache, because a project
that was never opened in the editor has no other way to resolve their names.

Data that those scripts name literally travels with them: an existing
``"res://….json"``-style file, and the plain files of a directory that a script
concatenates names onto (``"res://locales/" + code``). Files that are only named
inside other data (content packs, imported textures) are not followed; a
never-imported fixture could not load them anyway.
"""
from pathlib import Path
import re
import shutil

_SCRIPT_LITERAL = re.compile(r'"res://([^"\n]+\.gd)"')
_DATA_LITERAL = re.compile(r'"res://([^"\n]*[^"\n/])"')
_DIRECTORY_PREFIX = re.compile(r'"res://([^"\n]+)/"\s*\+')
_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')
_IDENTIFIER = re.compile(r"(?<![\w.])[A-Z]\w*")
_CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
_EXTENDS = re.compile(r'^extends\s+("res://[^"\n]+"|[\w.]+)', re.M)


def _code_without_strings(text):
    lines = []
    for line in text.splitlines():
        lines.append(_STRING.sub('""', line).split("#", 1)[0])
    return "\n".join(lines)


def global_classes(root):
    """Map each ``class_name`` declared below ``scripts/`` to its relative path."""
    classes = {}
    for path in sorted((root / "scripts").rglob("*.gd")):
        declared = _CLASS_NAME.search(path.read_text())
        if declared:
            classes[declared.group(1)] = path.relative_to(root).as_posix()
    return classes


def direct_dependencies(root, text, classes, own_path=None):
    """Relative script paths that ``text`` names by path or by global class."""
    found = set()
    for relative in _SCRIPT_LITERAL.findall(text):
        if not (root / relative).is_file():
            raise FileNotFoundError(f"res://{relative} is referenced but missing from {root}")
        found.add(relative)
    for name in set(_IDENTIFIER.findall(_code_without_strings(text))):
        if name in classes:
            found.add(classes[name])
    found.discard(own_path)
    return found


def script_closure(root, source):
    """All production scripts ``source`` needs, transitively, without itself."""
    root = Path(root)
    source = Path(source)
    classes = global_classes(root)
    try:
        own = source.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        own = None  # e.g. an older baseline copy of a production script
    pending = sorted(direct_dependencies(root, source.read_text(), classes, own))
    closure = []
    while pending:
        relative = pending.pop()
        if relative in closure or relative == own:
            continue
        closure.append(relative)
        pending.extend(direct_dependencies(root, (root / relative).read_text(), classes, relative))
    return sorted(closure)


def data_files(root, scripts):
    """Existing non-script files the given script files name literally."""
    root = Path(root)
    found = set()
    for script in scripts:
        text = Path(script).read_text()
        for relative in _DATA_LITERAL.findall(text):
            if not relative.endswith(".gd") and (root / relative).is_file():
                found.add(relative)
        for relative in _DIRECTORY_PREFIX.findall(text):
            if (root / relative).is_dir():
                found.update(path.relative_to(root).as_posix() for path in (root / relative).iterdir() if path.is_file())
    return sorted(found)


def _base_class(root, relative, by_path):
    declared = _EXTENDS.search((root / relative).read_text())
    if not declared:
        return "RefCounted"
    base = declared.group(1)
    if base.startswith('"'):
        return by_path.get(base[7:-1], "RefCounted")
    return base.split(".")[0]


def install(root, folder, source):
    """Copy ``source``'s scripts and literal data into ``folder``; return the paths."""
    root = Path(root)
    folder = Path(folder)
    closure = script_closure(root, source)
    data = data_files(root, [Path(source)] + [root / relative for relative in closure])
    for relative in closure + data:
        target = folder / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, target)
    by_path = {path: name for name, path in global_classes(root).items()}
    entries = []
    for relative in closure:
        if relative not in by_path:
            continue
        entries.append('{\n"base": &"%s",\n"class": &"%s",\n"icon": "",\n"is_abstract": false,\n"is_tool": false,\n"language": &"GDScript",\n"path": "res://%s"\n}'
                       % (_base_class(root, relative, by_path), by_path[relative], relative))
    if entries:
        cache = folder / ".godot/global_script_class_cache.cfg"
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text("list=[" + ", ".join(entries) + "]\n")
    return closure + data
