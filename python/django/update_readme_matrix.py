#!/usr/bin/env python
"""Update README.md with OpenTelemetry package matrix."""
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

def update_readme_matrix(readme_path: Path, matrix_content: str):
    """Update the README.md file with the new matrix content."""
    
    # Read the current README content
    with open(readme_path, 'r') as f:
        content = f.read()
    
    # Create the new matrix section
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    new_matrix_section = f"""## OpenTelemetry Package Matrix

This matrix shows the OpenTelemetry packages installed in each test environment:

```
{matrix_content}
```

*Last updated: {timestamp}*

> **Note**: This matrix is automatically updated by GitHub Actions when tests are run."""
    
    # Check if matrix section already exists
    matrix_pattern = r'## OpenTelemetry Package Matrix.*?(?=\n## |\Z)'
    match = re.search(matrix_pattern, content, re.DOTALL)
    
    if match:
        # Replace existing matrix section
        new_content = re.sub(matrix_pattern, new_matrix_section, content, flags=re.DOTALL)
    else:
        # Append matrix section at the end
        new_content = content.rstrip() + '\n\n' + new_matrix_section + '\n'
    
    # Write the updated content
    with open(readme_path, 'w') as f:
        f.write(new_content)
    
    print(f"Updated {readme_path} with new matrix content")

def main():
    if len(sys.argv) != 2:
        print("Usage: python update_readme_matrix.py <matrix_file>")
        sys.exit(1)
    
    matrix_file = Path(sys.argv[1])
    readme_file = Path("README.md")
    
    if not matrix_file.exists():
        print(f"Matrix file {matrix_file} not found")
        sys.exit(1)
    
    if not readme_file.exists():
        print(f"README.md not found")
        sys.exit(1)
    
    # Read matrix content
    with open(matrix_file, 'r') as f:
        matrix_content = f.read().strip()
    
    # Update README
    update_readme_matrix(readme_file, matrix_content)

if __name__ == '__main__':
    main() 