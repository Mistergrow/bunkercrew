#!/usr/bin/env python3
"""Check DE/EN catalogs and statically trace this project's visible text sources.

Uses Python's standard library. It does not translate or modify source files.
Run from any directory; --root supports isolated fixtures and alternate checkouts.
"""
from __future__ import annotations

import argparse
import ast
from bisect import bisect_right
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys


TOKEN = re.compile(
    r'\#[^\n]*|(?:r)?"""[\s\S]*?"""|(?:r)?\'\'\'[\s\S]*?\'\'\'|'
    r'(?:r)?"(?:\\.|[^"\\])*"|(?:r)?\'(?:\\.|[^\'\\])*\'|'
    r'[A-Za-z_][A-Za-z_0-9]*|(?:\d+(?:\.\d*)?|\.\d+)|'
    r'==|!=|:=|\+=|-=|<=|>=|->|\s+|.', re.MULTILINE
)
TEXT_FIELDS = {
    "title", "label", "detail", "description", "benefit", "note", "text",
    "reason", "arrows", "source_text", "message", "hint", "tooltip", "error",
}
# This authored schema includes paragraph arrays, not only short card labels.
SCOPED_TEXT_FIELDS = {
    "scripts/solo_story_catalog.gd": {"summary", "objective", "body", "name", "role", "job_title", "intro", "rescue", "after"},
    "scripts/solo_tutorial_catalog.gd": {"body"},
}
TEXT_PROPERTIES = {
    "text", "tooltip_text", "placeholder_text", "dialog_text", "title",
    "status_label", "error_message", "connection_hint", "last_error", "notice", "mapping_hint",
}
TEXT_CONSTANTS = {
    "RESOURCE_NAMES", "PHASES", "MODE_TITLES", "MODE_DETAILS", "CREW_ROLES",
    "WORLD_CAPTIONS", "UPGRADE_TECH_NAMES", "LABELS",
}
TEXT_RETURNS = {
    "prompt", "interaction_title", "action_hint", "controls_hint", "world_status",
    "status_text", "objective", "act_title", "recipe_lock", "requirement",
    "weapon_name", "speaker_name", "display_name", "resource_quantity",
    "_build_notice", "_expansion_notice", "input_status", "recipe_text",
}
# Argument positions, not all literals on a line: callbacks can contain input IDs.
RENDER_CALLS = {
    "Art.text": (2,), "UiArt.text": (2,), "UiArt.centered": (2,),
    "UiArt.world_label": (2, 3), "UiArt.wrap_text": (0,),
    "draw_string": (2,), "draw_multiline_string": (2,),
    "get_string_size": (0,), "get_multiline_string_size": (0,),
    "notify": (0,), "_fail": (0,), "_button": (0,), "_field": (1,),
    "_instruction": (2, 3), "_wrap": (0,), "_wrap_lines": (0,),
    "add_item": (0,), "set_tab_title": (1,), "set_item_text": (1,),
    "tr": (0,), "tr_n": (0, 1), "TranslationServer.translate": (0,),
    "error.emit": (0,), "disconnected.emit": (0,), "public_address_ready.emit": (1,),
}
# These APIs consume identifiers, paths, colors or diagnostic messages.
TECHNICAL_CALLS = {
    "assert", "push_error", "push_warning", "print", "printerr", "print_debug",
    "load", "preload", "Color", "NodePath", "StringName", "get_node",
    "get_node_or_null", "find_child", "find_children", "is_in_group",
    "add_to_group", "remove_from_group", "has_method", "has_signal",
    "get_nodes_in_group", "get_first_node_in_group",
    "has_action", "is_action_pressed", "is_action_just_pressed",
    "is_action_released", "is_action_just_released", "has_meta",
    "resource_path", "set_shader_parameter", "get_shader_parameter",
    "error_string", "globalize_path", "localize_path",
}
LOOKUP_CALLS = {"get", "get_meta", "has", "has_all", "contains", "begins_with", "ends_with"}
LOOKUP_ID_FIELDS = {
    "id", "kind", "type", "parent", "path", "icon", "portrait", "state",
    "environment", "build_type", "position", "character_id", "speaker_id",
    "weapon", "action", "group", "name", "status", "phase",
}
DATA_ID_FIELDS = LOOKUP_ID_FIELDS - {"name"} | {"tech", "speaker", "voice_path", "animation", "family"}
ID_ARGUMENTS = {
    "resource_quantity": (0,), "node_data": (0,), "requirement": (0,),
    "has_upgrade": (0,), "profile": (0,), "is_completed": (0,),
}
# Only selector arguments are machine IDs; defaults and returned catalog text
# still need translations. Qualified calls avoid exempting unrelated UI helpers.
ID_CALL_ARGUMENTS = {
    "ProjectSettings.get_setting": (0,),
    "CampaignCatalog.node": (0,), "CampaignCatalog.journey": (0,),
    "CampaignCatalog.stop": (0,), "CampaignCatalog.route_fuel": (0, 1),
    "InputLabels.action": (1,), "InputLabels.menu": (1,),
}
# Local lookup helpers return visible text while accepting only machine IDs.
# Scope them by file and exact call name so other UI helpers remain checked.
SCOPED_ID_CALL_ARGUMENTS = {
    ("scripts/help_manual_catalog.gd", "_recipe"): (0,),
    ("scripts/solo_tutorial_controller.gd", "Labels.action"): (1,),
    ("scripts/solo_tutorial_controller.gd", "Labels.menu"): (1,),
    ("scripts/solo_tutorial_controller.gd", "_menu_label"): (1,),
}
# This verifier exposes machine diagnostics only to tests; Session._fail is visible.
DIAGNOSTIC_CALLS = {("scripts/network_world.gd", "_fail")}
DIAGNOSTIC_PROPERTIES = {("scripts/network_world.gd", "last_error"),
                         ("scripts/environment_acoustics.gd", "title")}
IDENTITY_TEXT = {
    "MARA", "BRANKO", "IVO", "SAN-1", "SFX", "UDP", "TCP", "IPv4",
    "IP", "ENet", "Godot", "FPS", "ms", "px", "m", "s", "HP", "XP",
    "LMB", "RMB", "RT", "RS", "LB", "RB", "L3", "R3", "LS",
    "Enter/X", "Num*/L3", "Num* / L3", "Tab", "Enter", "Esc",
    "de", "en", "DE", "EN",
}
FORMATS = re.compile(r'%([-+0 #]*)([0-9]*)(?:\.([0-9]+))?([scdiouxXfFeEgGv%])')
UNAMBIGUOUS_FORMAT = re.compile(r'%(?:[-+0#]*[0-9]*(?:\.[0-9]+)?)[scdiouxXfFeEgGv%]')


@dataclass(frozen=True)
class Token:
    value: str
    line: int
    start: int
    end: int
    string: bool = False


@dataclass(frozen=True)
class Reference:
    path: str
    line: int
    source: str
    reason: str


def tokenize(source: str) -> list[Token]:
    starts = [0] + [match.end() for match in re.finditer('\n', source)]
    result = []
    for match in TOKEN.finditer(source):
        raw = match[0]
        if raw.isspace() or raw.startswith('#'):
            continue
        is_string = raw.startswith(('"', "'", 'r"', "r'"))
        value = ast.literal_eval(raw) if is_string else raw
        result.append(Token(value, bisect_right(starts, match.start()), match.start(), match.end(), is_string))
    return result


class SourceScan:
    def __init__(self, path: str, source: str):
        self.path = path
        self.tokens = tokenize(source)
        self.pairs: dict[int, int] = {}
        self.parent: dict[int, int | None] = {}
        self.scopes: dict[int, str] = {}
        self.bindings: dict[tuple[str, str], list[tuple[int, int]]] = defaultdict(list)
        self.suppressed: dict[int, str] = {}
        self.references: set[Reference] = set()
        self.formats: set[str] = set()
        self.exclusions: Counter = Counter()
        self.sinks = 0
        self._seen: set[tuple[int, int, str]] = set()
        stack = []
        for index, token in enumerate(self.tokens):
            self.parent[index] = stack[-1] if stack else None
            if token.string:
                continue
            if token.value in ('(', '[', '{'):
                stack.append(index)
            elif token.value in (')', ']', '}'):
                if not stack or {'(': ')', '[': ']', '{': '}'}[self.tokens[stack[-1]].value] != token.value:
                    raise ValueError(f'{path}:{token.line}: unmatched {token.value}')
                opening = stack.pop()
                self.pairs[opening] = index
        if stack:
            raise ValueError(f'{path}:{self.tokens[stack[-1]].line}: unclosed delimiter')
        self.openings = {closing: opening for opening, closing in self.pairs.items()}

    def assignment_name(self, index: int) -> int:
        previous = index - 1
        # A typed collection: var lines: Array[String] = ...
        if previous in self.openings:
            opening = self.openings[previous]
            if opening >= 3 and self.tokens[opening - 2].value == ':' and self.tokens[opening - 2].line == self.tokens[opening].line:
                return opening - 3
            # A display dictionary field: result["text"] = ...
            if previous == opening + 2 and self.tokens[opening + 1].string:
                return opening + 1
        if index >= 3 and self.tokens[index - 2].value == ':':
            return index - 3
        return previous

    def arguments(self, opening: int) -> list[tuple[int, int]]:
        end = self.pairs[opening]
        result, start, index = [], opening + 1, opening + 1
        while index < end:
            if index in self.pairs:
                index = self.pairs[index] + 1
                continue
            if self.tokens[index].value == ',' and not self.tokens[index].string:
                result.append((start, index))
                start = index + 1
            index += 1
        if start < end:
            result.append((start, end))
        return result

    def statement_end(self, index: int) -> int:
        line = self.tokens[index].line
        while index < len(self.tokens):
            if self.tokens[index].line > line:
                break
            if index in self.pairs:
                index = self.pairs[index] + 1
                if index: line = self.tokens[index - 1].line
            else:
                index += 1
        return index

    def call_name(self, opening: int) -> str:
        if opening == 0 or self.tokens[opening - 1].string:
            return ''
        names = [self.tokens[opening - 1].value]
        index = opening - 2
        while index >= 1 and self.tokens[index].value == '.':
            names.insert(0, self.tokens[index - 1].value)
            index -= 2
        return '.'.join(names)

    def suppress(self, span: tuple[int, int], reason: str) -> None:
        for index in range(*span):
            self.suppressed[index] = reason

    def _prepare(self) -> None:
        scope = ''
        for index, token in enumerate(self.tokens):
            if token.value == 'func' and index + 1 < len(self.tokens) and self.tokens[index + 1].value.isidentifier():
                scope = self.tokens[index + 1].value
            self.scopes[index] = scope
            if token.value in ('=', ':=', '+=') and not token.string and index > 0:
                name_index = self.assignment_name(index)
                name = self.tokens[name_index].value
                if self.path == 'scripts/network_session.gd' and scope == '_valid_relay_control' and name == 'keys':
                    self.suppress((index + 1, self.statement_end(index + 1)), 'relay control schema field names')
                parent = self.parent.get(index)
                parameter = parent is not None and self.tokens[parent].value == '(' and parent >= 2 and self.tokens[parent - 2].value == 'func'
                if not parameter and re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', name):
                    self.bindings[(scope, name)].append((index + 1, self.statement_end(index + 1)))
                    # Fields assigned in _ready/_process are consumed by _draw.
                    if (name_index > 0 and self.tokens[name_index - 1].value == '.') or name in TEXT_PROPERTIES:
                        self.bindings[('', name)].append((index + 1, self.statement_end(index + 1)))
            if index not in self.pairs or token.value != '(':
                continue
            name = self.call_name(index)
            method = name.split('.')[-1]
            arguments = self.arguments(index)
            if method in ('append', 'append_array', 'push_back') and name.count('.') == 1:
                self.bindings[(scope, name.split('.')[0])].extend(arguments)
            if (self.path, method) in DIAGNOSTIC_CALLS:
                self.suppress((index + 1, self.pairs[index]), 'internal snapshot diagnostic')
            elif method in TECHNICAL_CALLS:
                self.suppress((index + 1, self.pairs[index]), 'technical API: ' + method)
            elif method in LOOKUP_CALLS and arguments:
                self.suppress(arguments[0], 'dictionary/property identifier')
                start, end = arguments[0]
                if end - start == 1 and self.tokens[start].value in LOOKUP_ID_FIELDS:
                    for argument in arguments[1:]:
                        self.suppress(argument, 'identifier fallback')
                elif len(arguments) == 2:
                    # A missing map key deliberately falls back to the same ID.
                    key_tokens = self.tokens[start:end]
                    fallback = self.tokens[slice(*arguments[1])]
                    if [t.value for t in key_tokens] == [t.value for t in fallback]:
                        self.suppress(arguments[1], 'identifier fallback')
            for position in (ID_ARGUMENTS.get(method, ()) + ID_CALL_ARGUMENTS.get(name, ()) +
                             SCOPED_ID_CALL_ARGUMENTS.get((self.path, name), ())):
                if position < len(arguments):
                    self.suppress(arguments[position], 'catalog selector identifier')
        for index, token in enumerate(self.tokens):
            if token.value == 'if' and not token.string:
                # Only a ternary predicate, not either displayed result branch.
                for end in range(index + 1, self.statement_end(index)):
                    if self.parent.get(end) == self.parent.get(index) and self.tokens[end].value == 'else':
                        self.suppress((index + 1, end), 'conditional predicate')
                        break
            if token.value == '[' and index > 0 and index in self.pairs:
                previous = self.tokens[index - 1]
                if previous.line == token.line and (previous.value.isidentifier() and previous.value not in ('return', 'in', 'else') or previous.value in (']', ')')):
                    self.suppress((index + 1, self.pairs[index]), 'collection index')
            if token.value == ':' and index > 0 and self.parent.get(index) is not None:
                parent = self.parent[index]
                if self.tokens[parent].value == '{' and self.tokens[index - 1].value in DATA_ID_FIELDS:
                    for start, end in self.arguments(parent):
                        if start <= index < end:
                            self.suppress((index + 1, end), 'catalog machine identifier')
                            break
            if not token.string:
                continue
            before = self.tokens[index - 1].value if index else ''
            after = self.tokens[index + 1].value if index + 1 < len(self.tokens) else ''
            if after == ':':
                self.suppressed[index] = 'dictionary or match key'
            if before in ('==', '!=', 'in') or after in ('==', '!=', 'in'):
                self.suppressed[index] = 'comparison/identifier'
            parent = self.parent[index]
            if parent is not None and self.tokens[parent].value == '[' and parent > 0:
                preceding = self.tokens[parent - 1]
                if preceding.value == 'in' or (preceding.value not in ('=', ':=', ':', ',', '(', 'return', 'else') and preceding.line == self.tokens[parent].line and preceding.value.isidentifier()):
                    self.suppressed[index] = 'collection membership/index'

    def collect(self, span: tuple[int, int], reason: str, follow: bool = True) -> None:
        start, end = span
        scope = self.scopes.get(start, '')
        signature = (start, end, scope)
        if signature in self._seen:
            return
        self._seen.add(signature)
        for index in range(start, end):
            token = self.tokens[index]
            if token.string:
                excluded = self.suppressed.get(index)
                if excluded:
                    self.exclusions[excluded] += 1
                    continue
                self.references.add(Reference(self.path, token.line, token.value, reason))
            elif follow and token.value.isidentifier() and index not in self.suppressed:
                before = self.tokens[index - 1].value if index else ''
                after = self.tokens[index + 1].value if index + 1 < len(self.tokens) else ''
                if before == '.' or after in ('.', '('):
                    continue
                for definition in self.bindings.get((scope, token.value), []) + self.bindings.get(('', token.value), []):
                    self.collect(definition, 'display variable ' + token.value)

    def scan(self) -> None:
        self._prepare()
        for index, token in enumerate(self.tokens):
            if index in self.pairs and token.value == '(':
                if index >= 2 and self.tokens[index - 2].value == 'func':
                    continue
                name = self.call_name(index)
                method = name.split('.')[-1]
                arguments = self.arguments(index)
                positions = RENDER_CALLS.get(name, RENDER_CALLS.get(method, ()))
                # Inventory.add_item takes a resource ID; OptionButton.add_item takes text.
                if method == 'add_item' and not self.path.endswith('_panel.gd'):
                    positions = ()
                if name in ('LocaleText.text', 'LocaleText.format', 'L.text', 'L.format'):
                    positions = (0, 1) if method == 'format' else (0,)
                    if method == 'format' and arguments:
                        for at in range(*arguments[0]):
                            if self.tokens[at].string and at not in self.suppressed:
                                self.formats.add(self.tokens[at].value)
                if method in TECHNICAL_CALLS:
                    continue
                if (self.path, method) in DIAGNOSTIC_CALLS:
                    continue
                if self.path == 'scripts/network_transport.gd' and method == 'report':
                    positions = (1,)
                for position in positions:
                    if position < len(arguments):
                        self.sinks += 1
                        self.collect(arguments[position], 'text API ' + name)
            if token.value in ('=', ':=', '+=') and not token.string and index > 0:
                name_index = self.assignment_name(index)
                name = self.tokens[name_index].value
                if (name in TEXT_PROPERTIES or name in TEXT_CONSTANTS) and (self.path, name) not in DIAGNOSTIC_PROPERTIES:
                    self.collect((index + 1, self.statement_end(index + 1)), 'display property/constant ' + name)
            if token.value == 'return' and self.scopes.get(index) in TEXT_RETURNS:
                self.collect((index + 1, self.statement_end(index + 1)), 'text return ' + self.scopes[index])
            if token.value == ':' and not token.string and index > 0:
                key = self.tokens[index - 1]
                parent = self.parent[index]
                if parent is not None and self.tokens[parent].value == '{':
                    visible = key.value in TEXT_FIELDS or key.value in SCOPED_TEXT_FIELDS.get(self.path, set()) or key.value == 'variants' or (key.value == 'name' and self.path == 'scripts/expansion_site.gd')
                    if visible:
                        for start, end in self.arguments(parent):
                            if start <= index < end:
                                self.collect((index + 1, end), 'catalog/display field ' + key.value)
                                break


def exclusion(source: str) -> str | None:
    if not source or not any(character.isalpha() for character in source):
        return 'empty, numeric, or punctuation-only label'
    if source in IDENTITY_TEXT or re.fullmatch(r'(?:[A-Z]|F\d{1,2}|[IVX]+)', source):
        return 'proper name, unit, or input/technical label'
    if re.fullmatch(r'[-+]?\d+(?:[.,]\d+)?\s*(?:M|m|px|ms|Hz|kHz|dB)', source):
        return 'numeric measurement with invariant unit'
    if source.startswith(('res://', 'user://', 'uid://', 'http://', 'https://', 'ws://', 'wss://')):
        return 'resource path or protocol URL'
    if re.fullmatch(r'#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})', source):
        return 'color literal'
    return None


def load_catalog(path: Path, issues: list[str]) -> dict[str, str]:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result: issues.append(f'{path}: duplicate key {key!r}')
            result[key] = value
        return result
    try:
        result = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=pairs)
    except (OSError, ValueError) as error:
        issues.append(f'{path}: {error}')
        return {}
    if not isinstance(result, dict):
        issues.append(f'{path}: catalog must be a JSON object')
        return {}
    for key, value in result.items():
        if not key.strip() or not isinstance(value, str) or not value.strip():
            issues.append(f'{path}: nonempty string value required for {key!r}')
    return {key: value for key, value in result.items() if isinstance(value, str)}


def format_signature(text: str, formatted: bool) -> tuple[list[str], list[str]]:
    signature, invalid = [], []
    position = 0
    while position < len(text):
        if text[position] != '%':
            position += 1
            continue
        match = FORMATS.match(text, position)
        if match and (formatted or ' ' not in match[1]):
            kind = match[4]
            if kind != '%':
                signature.append('integer' if kind in 'diouxX' else 'float' if kind in 'fFeEgG' else kind)
            position = match.end()
        else:
            if formatted: invalid.append(text[position:position + 12])
            position += 1
    return signature, invalid


def check_repository(root: Path) -> dict:
    issues: list[str] = []
    de = load_catalog(root / 'locales/de.json', issues)
    en = load_catalog(root / 'locales/en.json', issues)
    for key in sorted(de.keys() - en.keys()): issues.append(f'locales/en.json: missing key {key!r}')
    for key in sorted(en.keys() - de.keys()): issues.append(f'locales/de.json: missing key {key!r}')
    references: set[Reference] = set()
    formats: set[str] = set()
    excluded: Counter = Counter()
    counts: Counter = Counter()
    for directory, extension in [('scripts', '*.gd'), ('scenes', '*.tscn')]:
        for path in sorted((root / directory).rglob(extension)):
            relative = str(path.relative_to(root))
            counts[directory] += 1
            try:
                scan = SourceScan(relative, path.read_text(encoding='utf-8'))
                scan.scan()
                references.update(scan.references)
                formats.update(scan.formats)
                excluded.update(scan.exclusions)
                counts['text_sinks'] += scan.sinks
            except (ValueError, SyntaxError) as error:
                issues.append(f'{relative}: source scan failed: {error}')
    environment_file = root / 'assets/environments/catalog.json'
    if environment_file.exists():
        try:
            data = json.loads(environment_file.read_text(encoding='utf-8'))
            for environment in data.get('environments', []):
                counts['environment_entries'] += 1
                for field in ('title', 'detail'):
                    value = environment.get(field)
                    if not isinstance(value, str) or not value.strip():
                        issues.append(f'assets/environments/catalog.json: {environment.get("id")}.{field} is empty or not text')
                    else:
                        references.add(Reference('assets/environments/catalog.json', 1, value, f'environment {environment.get("id")}.{field}'))
        except (OSError, ValueError, AttributeError) as error:
            issues.append(f'assets/environments/catalog.json: {error}')
    # Core display strings moved out of GDScript; keep the same audit coverage.
    for category in ('characters', 'items', 'workshop_recipes', 'station_recipes'):
        catalog_file = root / 'assets/content/core' / (category + '.json')
        if not catalog_file.exists():
            continue
        relative = str(catalog_file.relative_to(root))
        try:
            content = json.loads(catalog_file.read_text(encoding='utf-8'))
            for entry in content.get(category, []):
                counts['content_entries'] += 1
                for field in ('title', 'detail', 'special', 'label', 'note'):
                    if field not in entry:
                        continue
                    value = entry[field]
                    if not isinstance(value, str) or not value.strip():
                        issues.append(f'{relative}: {entry.get("id")}.{field} is empty or not text')
                    else:
                        references.add(Reference(relative, 1, value, f'content {entry.get("id")}.{field}'))
        except (OSError, ValueError, AttributeError, TypeError) as error:
            issues.append(f'{relative}: {error}')
    for source in sorted(de.keys() & en.keys()):
        if de[source] != source: issues.append(f'locales/de.json: source msgid differs from German value: {source!r}')
        formatted = source in formats or bool(UNAMBIGUOUS_FORMAT.search(source))
        original, bad_original = format_signature(source, formatted)
        translated, bad_translated = format_signature(en[source], formatted)
        if bad_original or bad_translated:
            issues.append(f'locales: invalid formatting in {source!r}: DE {bad_original}, EN {bad_translated}')
        if original != translated:
            issues.append(f'locales: placeholder mismatch for {source!r}: DE {original}, EN {translated}')
    # Match exactly the runtime's supported uppercase/capitalized source aliases.
    aliases = set(de) | set(en.values())
    for source in list(aliases):
        aliases.add(source.upper())
        aliases.add(' '.join(word[:1].upper() + word[1:].lower() for word in source.split(' ')))
    missing, covered = [], set()
    for reference in sorted(references, key=lambda item: (item.path, item.line, item.source)):
        reason = exclusion(reference.source)
        if reason:
            excluded[reason] += 1
        elif reference.source in aliases:
            covered.add(reference.source)
        else:
            missing.append(asdict(reference))
            issues.append(f'{reference.path}:{reference.line}: missing message {reference.source!r} [{reference.reason}]')
    return {
        'ok': not issues, 'catalog_entries': {'de': len(de), 'en': len(en)},
        'scanned': dict(counts), 'source_occurrences': len(references),
        'covered_source_messages': len(covered), 'missing_sources': missing,
        'exclusions': dict(sorted(excluded.items())), 'issues': issues,
        'scope': 'Static string tokens in known render/text APIs, explicit LocaleText/L wrappers, display properties, text returns, tracked local bindings, catalog fields, scenes, environment and core content JSON. Runtime-created/external text and final layout require runtime tests.',
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--json', type=Path, help='write the complete machine-readable report')
    args = parser.parse_args()
    report = check_repository(args.root.resolve())
    print(f"LOCALES {'PASS' if report['ok'] else 'FAIL'}: DE {report['catalog_entries']['de']}, EN {report['catalog_entries']['en']} messages")
    print(f"Sources: {report['scanned'].get('scripts', 0)} scripts, {report['scanned'].get('scenes', 0)} scenes, {report['scanned'].get('environment_entries', 0)} environment entries; {report['covered_source_messages']} covered messages")
    print(f"Checked {report['scanned'].get('text_sinks', 0)} text API arguments and {report['source_occurrences']} source occurrences; {len(report['issues'])} issues")
    for issue in report['issues']: print('  ' + issue)
    print('Explicit exclusions: ' + ', '.join(f'{reason}: {count}' for reason, count in report['exclusions'].items()))
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
