#!/usr/bin/env python3
"""Generate OpenTelemetry package matrix from captured data."""
import sys
from pathlib import Path

def main():
    data_dir = Path('all_package_data')
    if not data_dir.exists():
        print("| Environment | OTEL Packages |")
        print("|------------|--------------|")
        print("| No data | No package data found |")
        return
    
    matrix_lines = ['| Environment | OTEL Packages |', '|------------|--------------|']
    
    for file_path in sorted(data_dir.glob('py*.txt')):
        if file_path.stat().st_size > 0:
            with open(file_path) as f:
                content = f.read().strip()
                if content:
                    lines = content.split('\n')
                    
                    # Handle direct table format or old format
                    for line in lines:
                        line = line.strip()
                        if line.startswith('|') and not line.startswith('|--') and 'Environment' not in line:
                            # This is already a table row, add it directly
                            matrix_lines.append(line)
                        elif line.startswith('=== ') and line.endswith(' ==='):
                            # Old format - process as before
                            current_env = line[4:-4]
                            packages = []
                        elif line.startswith('opentelemetry') and '==' in line:
                            packages.append(line)
    
    # Write matrix to file
    with open('package_matrix.txt', 'w') as f:
        f.write('\n'.join(matrix_lines))
    
    # Print to stdout
    print('\n'.join(matrix_lines))

if __name__ == '__main__':
    main()