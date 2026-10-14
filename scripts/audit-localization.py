#!/usr/bin/env python3
"""Audit built-in Chinese UI/status strings against all shipped language tables."""
from pathlib import Path
import json
import re
import sys

PROJECT = Path(__file__).resolve().parent.parent
PLACEHOLDER = re.compile(r'%(?:([1-9]\d*)\$)?[-+0-9.]*(?:ll|l)?([@diufgGxX])')


def read_table(path):
    pairs = re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', path.read_text(), re.M)
    return {json.loads('"' + key + '"'): json.loads('"' + value + '"') for key, value in pairs}


def literals(source):
    index = 0
    while index < len(source):
        if source.startswith('//', index):
            end = source.find('\n', index)
            index = len(source) if end < 0 else end + 1
        elif source.startswith('/*', index):
            end = source.find('*/', index + 2)
            index = len(source) if end < 0 else end + 2
        elif source[index] == '"':
            index += 1
            result = ''
            while index < len(source) and source[index] != '"':
                if source.startswith('\\(', index):
                    depth = 1
                    index += 2
                    while index < len(source) and depth:
                        if source[index] == '"':
                            index += 1
                            while index < len(source) and source[index] != '"':
                                index += 2 if source[index] == '\\' else 1
                        elif source[index] == '(':
                            depth += 1
                        elif source[index] == ')':
                            depth -= 1
                        index += 1
                    result += '%@'
                elif source[index] == '\\' and index + 1 < len(source):
                    result += {'n': '\n', 't': '\t', 'r': '\r'}.get(source[index + 1], source[index + 1])
                    index += 2
                else:
                    result += source[index]
                    index += 1
            index += 1
            yield result
        else:
            index += 1


def format_arguments(text):
    arguments = []
    for index, match in enumerate(PLACEHOLDER.finditer(text), start=1):
        position = int(match.group(1) or index)
        kind = match.group(2)
        arguments.append((position, 'd' if kind == 'i' else kind))
    return sorted(arguments)


def audit():
    references = {}
    for path in sorted((PROJECT / 'Sources/XvicoApp').rglob('*.swift')):
        for text in literals(path.read_text()):
            if re.search(r'[\u4e00-\u9fff]', text):
                references.setdefault(text, set()).add(str(path.relative_to(PROJECT)))
    tables = {language: read_table(PROJECT / f'Sources/XvicoApp/Resources/Localization/{language}.lproj/Localizable.strings')
              for language in ['zh-Hans', 'en', 'ja', 'fr']}
    missing = {language: sorted(set(references) - set(table)) for language, table in tables.items()}
    format_mismatches = {language: [key for key in sorted(references.keys() & table.keys())
                                   if format_arguments(key) != format_arguments(table[key])]
                         for language, table in tables.items()}
    return {'sourceKeys': len(references), 'tableKeys': {key: len(value) for key, value in tables.items()},
            'missingCounts': {key: len(value) for key, value in missing.items()}, 'missing': missing,
            'formatMismatchCounts': {key: len(value) for key, value in format_mismatches.items()},
            'formatMismatches': format_mismatches,
            'references': {key: sorted(value) for key, value in references.items()}}


if __name__ == '__main__':
    report = audit()
    if '--json' in sys.argv:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(json.dumps({key: report[key] for key in ['sourceKeys', 'tableKeys', 'missingCounts', 'formatMismatchCounts']}, ensure_ascii=False, indent=2))
    if '--check' in sys.argv and (any(report['missingCounts'].values()) or any(report['formatMismatchCounts'].values())):
        sys.exit(1)
