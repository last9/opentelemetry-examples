# GitHub Actions Workflows

This directory contains GitHub Actions workflows for automated testing and documentation updates.

## Workflows

### test-matrix.yml

This workflow automatically:

1. **Runs tox tests** - Executes the full test matrix defined in `tox.ini`
2. **Generates package matrix** - Uses `list_otel_packages.py` to collect OpenTelemetry packages from each test environment
3. **Updates README.md** - Automatically updates the "OpenTelemetry Package Matrix" section with the latest package information
4. **Commits changes** - If the matrix has changed, it commits and pushes the updated README

#### Triggers

- Push to `main` or `master` branches
- Pull requests to `main` or `master` branches
- Manual trigger via `workflow_dispatch`

#### Permissions

The workflow requires:
- `contents: write` - To commit changes to README.md
- `pull-requests: write` - To comment on PRs (if needed)

#### Files Modified

- `README.md` - Updated with the latest OpenTelemetry package matrix

#### Dependencies

- `tox.ini` - Defines the test matrix
- `list_otel_packages.py` - Generates the package matrix
- `update_readme_matrix.py` - Updates the README with new matrix content

## Setup

1. Ensure the repository has the required files:
   - `tox.ini` at the repository root
   - `list_otel_packages.py` in the Django project directory
   - `update_readme_matrix.py` in the Django project directory

2. The workflow will automatically run on pushes and pull requests to main branches.

3. The matrix will be updated automatically after each successful test run.

## Manual Execution

To manually trigger the workflow:

1. Go to the "Actions" tab in your GitHub repository
2. Select "Test Matrix and Update README"
3. Click "Run workflow"
4. Choose the branch and click "Run workflow" 