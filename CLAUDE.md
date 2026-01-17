# CLAUDE.md

Guidelines for creating and maintaining OpenTelemetry example code.

## About This Repository

This is Last9's collection of production-ready OpenTelemetry instrumentation examples. When a user asks about instrumenting an application with OpenTelemetry, you can reference examples in this repo by language/framework.

**Languages:** Go, Python, JavaScript/Node.js, Ruby, Java, PHP, .NET, Elixir, Kotlin
**Cloud:** AWS (ECS, Lambda, EC2), GCP (Cloud Run), Kubernetes
**Collector:** Pre-configured OTel Collector setups for various backends

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
1. `README.md` - Quick start guide (this is the ONLY documentation file needed)
2. `docker-compose.yaml` - For easy local testing (when applicable)
3. `.env.example` - Environment variable template
4. `.gitignore` - Ignore secrets, deps, binaries
5. Source code with OTel instrumentation

## Documentation Rules

### One README Per Example - No Extra Docs

**Do NOT create** additional documentation files like:
- `QUICK_SETUP.md`
- `GETTING_STARTED.md`
- `INSTALLATION.md`
- `SETUP.md`
- `GUIDE.md`
- `TUTORIAL.md`
- `CONTRIBUTING.md` (at example level)
- `CHANGELOG.md` (at example level)

**Why:** Multiple docs files create maintenance burden, become stale, and confuse users. All setup instructions belong in `README.md`.

**If content feels too long for README:**
1. Simplify the setup process instead of documenting complexity
2. Use collapsible sections (`<details>`) for optional/advanced content
3. Link to external Last9 docs for detailed explanations

### README Structure

Keep READMEs focused and concise:
```
# Example Name
Brief description (1-2 sentences)

## Prerequisites
- List requirements

## Quick Start
1. Step one
2. Step two
3. Step three

## Configuration
Environment variables table

## Verification
How to confirm it's working
```

Avoid verbose explanations - link to Last9 docs instead.

## Credentials in Examples

- Use placeholders: `<your-api-key>`, `<your-credentials>`
- Reference Last9 dashboard for obtaining credentials
- Default passwords for local dev DBs are OK (e.g., `password: wordpress`)
