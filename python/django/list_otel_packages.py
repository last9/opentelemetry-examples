#!/usr/bin/env python
"""Aggregate installed OpenTelemetry packages from tox environments."""
import subprocess
from pathlib import Path

TOX_DIR = Path(__file__).resolve().parents[1] / '.tox'

def get_packages(pip_path: Path):
    result = subprocess.run([str(pip_path), 'list', '--format=freeze'], capture_output=True, text=True, check=True)
    return sorted(pkg.split('==')[0] for pkg in result.stdout.splitlines() if pkg.startswith('opentelemetry'))

def main():
    rows = []
    for pip in TOX_DIR.glob('py*-django*/bin/pip'):
        env = pip.parent.parent.name
        pkgs = get_packages(pip)
        rows.append((env, ', '.join(pkgs)))
    if not rows:
        print('No tox environments found. Run "tox" first.')
        return
    header = '| Environment | OTEL Packages |\n|------------|--------------|'
    lines = [header] + [f'| {env} | {pkgs} |' for env, pkgs in rows]
    print('\n'.join(lines))

if __name__ == '__main__':
    main()
