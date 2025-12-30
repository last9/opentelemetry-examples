# CLAUDE.md

Guidelines for creating and maintaining OpenTelemetry example code.

## Repository Structure

Examples are organized by language/platform:
- `go/` - Go examples
- `php/` - PHP examples
- `python/` - Python examples
- `java/` - Java examples
- `javascript/` - JavaScript/Node.js examples
- `ruby/` - Ruby examples
- etc.

## Important Rules

### Do NOT Commit

- **Binaries** - No compiled executables, `.exe`, `.so`, `.dylib`, `.dll` files
- **Secrets** - No API keys, passwords, tokens, or credentials
- **Dependencies** - No `vendor/`, `node_modules/`, `.venv/`, etc.
- **IDE files** - No `.idea/`, `.vscode/` (unless shared configs)
- **OS files** - No `.DS_Store`, `Thumbs.db`
- **Build artifacts** - No `dist/`, `build/`, `target/`, `bin/`

### Always Include

- **`.gitignore`** - Every example directory must have a proper .gitignore
- **`README.md`** - Setup instructions and usage
- **`.env.example`** - Template for environment variables (no real values)

## .gitignore Template

Every example should include a `.gitignore` with at minimum:

```gitignore
# Environment/secrets
.env
.env.local
.env.*.local

# Dependencies (language-specific)
/vendor/
/node_modules/
/.venv/
/target/
/bin/

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Logs
*.log

# Build artifacts
/dist/
/build/
```

## Example Format

Each example should have:
1. `README.md` - Quick start guide
2. `docker-compose.yaml` - For easy local testing (when applicable)
3. `.env.example` - Environment variable template
4. `.gitignore` - Ignore secrets, deps, binaries
5. Source code with OTel instrumentation

## Credentials in Examples

- Use placeholders: `<your-api-key>`, `<your-credentials>`
- Reference Last9 dashboard for obtaining credentials
- Default passwords for local dev DBs are OK (e.g., `password: wordpress`)
