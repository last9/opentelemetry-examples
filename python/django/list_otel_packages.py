#!/usr/bin/env python
"""Aggregate installed OpenTelemetry packages from tox environments."""
import subprocess
from pathlib import Path

TOX_DIR = Path(__file__).resolve().parents[1] / '.tox'

def get_packages(pip_path: Path):
    result = subprocess.run([str(pip_path), 'list', '--format=freeze'], capture_output=True, text=True, check=True)
    packages = []
    for pkg in result.stdout.splitlines():
        if pkg.startswith('opentelemetry'):
            if '==' in pkg:
                name, version = pkg.split('==', 1)
                packages.append((name, version))
            else:
                packages.append((pkg, 'unknown'))
    return sorted(packages)

def main():
    rows = []
    for pip in TOX_DIR.glob('py*-django*/bin/pip'):
        env = pip.parent.parent.name
        pkgs = get_packages(pip)
        if pkgs:
            # Format packages as "name==version"
            pkg_strings = [f"{name}=={version}" for name, version in pkgs]
            rows.append((env, ', '.join(pkg_strings)))
    if not rows:
        print('No tox environments found. Run "tox" first.')
        return
    header = '| Environment | OTEL Packages |\n|------------|--------------|'
    lines = [header] + [f'| {env} | {pkgs} |' for env, pkgs in rows]
    print('\n'.join(lines))

if __name__ == '__main__':
    main()
