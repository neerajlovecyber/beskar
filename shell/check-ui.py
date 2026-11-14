#!/usr/bin/env python3
"""Check shared UI geometry conventions without starting the shell."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent


def without_comments(source):
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',
                  lambda m: m[0] if m[0].startswith('"') else ' ' * len(m[0]), source)


def calls(source, name):
    """Yield call arguments, respecting nested expressions and quoted labels."""
    for match in re.finditer(r'\b' + name + r'\(', source):
        if re.search(r'\bcomponent\s*$', source[:match.start()]):
            continue
        start = match.end()
        depth, quoted, escaped, args = 1, False, False, []
        for index in range(start, len(source)):
            char = source[index]
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char == '(':
                depth += 1
            elif char == ')':
                depth -= 1
                if depth == 0:
                    args.append(source[start:index].strip())
                    yield match.start(), args
                    break
            elif char == ',' and depth == 1:
                args.append(source[start:index].strip())
                start = index + 1


def check(path):
    source = without_comments(path.read_text())
    errors = []
    plain = re.sub(r'"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m[0]), source)

    def report(offset, reason):
        line = source.count('\n', 0, offset) + 1
        errors.append(f'{path.relative_to(ROOT.parent)}:{line}: {reason}')

    if path.name == 'geometry.plm':
        for match in re.finditer(r'\b(?:surface|component|prop|fact|model|event|service|every|on)\b', plain):
            report(match.start(), 'geometry must contain constants only')
        return errors

    for match in re.finditer(r'\bcorner:\s*(\d+(?:\.\d+)?)(?=\s*[;}\n]|$)', plain):
        if float(match[1]) >= 5:
            report(match.start(), 'use a shared corner role from common/geometry.plm')
    for match in re.finditer(r'\bgap:\s*[1-9]\d*(?:\.\d+)?(?=\s*[;}\n]|$)', plain):
        report(match.start(), 'use a shared spacing role')
    for match in re.finditer(r'\bsize:\s*(?:10\.5|11\.5|11|12|13|15)(?=\s*[;}\n]|$)', plain):
        report(match.start(), 'use a shared text-size role')

    sized_calls = {'Pill': (4,), 'IconButton': (5, 6, 8),
                   'IconTextButton': (8, 10), 'CardBg': (2,)}
    named_sizes = {'Pill': {'h'}, 'IconButton': {'w', 'h', 'radius'},
                   'IconTextButton': {'h', 'radius'}, 'CardBg': {'r'}}
    for name, positions in sized_calls.items():
        for offset, args in calls(source, name):
            for position in positions:
                if position < len(args) and re.fullmatch(r'\d+(?:\.\d+)?', args[position]):
                    report(offset, f'{name}: use the default or a shared size/corner role')
            for arg in args:
                match = re.fullmatch(r'(\w+)\s*:\s*\d+(?:\.\d+)?', arg)
                if match and match[1] in named_sizes[name]:
                    report(offset, f'{name}: named {match[1]} must use a shared role')

    if re.search(r'^library\s', source, re.MULTILINE):
        for match in re.finditer(r'\b(?:surface|service|permissions|model|fact|every)\b', plain):
            report(match.start(), 'rendering libraries must not own surfaces or data feeds')
    return errors


def main():
    errors = [error for path in sorted(ROOT.rglob('*.plm')) for error in check(path)]
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('UI standards passed: shared geometry and surface-free rendering libraries')
    return 0


if __name__ == '__main__':
    sys.exit(main())
