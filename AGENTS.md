# AGENTS.md - OpenClaw OpenTofu Hetzner

Agent coding guidelines for contributing to the OpenClaw OpenTofu Hetzner repository.

## Quick Reference

- **Primary Languages:** HCL (OpenTofu), Shell (Bash)
- **Infrastructure Tool:** OpenTofu >= 1.8 (OSS fork of Terraform)
- **Commit Style:** Conventional Commits (feat, fix, docs, chore, refactor, test)
- **Testing:** Validate OpenTofu syntax, test shell scripts with shellcheck
- **Pre-commit:** Run `make validate` and `make fmt` before committing

## Build, Lint & Test Commands

### Validation

```bash
make validate      # Validate OpenTofu + shell scripts (recommended single command)
make fmt           # Format all OpenTofu/HCL files
tofu fmt -check -recursive infra/  # Check formatting without changes
```

### Single Command Tests

All validation happens through `make validate`:
- Validates OpenTofu configuration in `infra/terraform/envs/prod/`
- Validates all shell scripts in `deploy/*.sh` and `scripts/*.sh` using `shellcheck`
- Tests run sequentially; fix any validation errors before proceeding

### OpenTofu Workflow

```bash
source config/inputs.sh    # Load Hetzner API token and config
make init                  # Initialize OpenTofu backend
make plan                  # Preview infrastructure changes (review before apply)
make apply                 # Apply changes (requires interactive confirmation)
make destroy               # Destroy all managed infrastructure (dangerous)
```

### Deployment & Operations

```bash
make bootstrap             # Run once after apply to set up OpenClaw
make deploy               # Pull latest image and restart container
make status               # Check VPS and container status
make logs                 # Stream Docker logs from VPS
make ssh                  # SSH as openclaw user
make tunnel               # SSH tunnel to gateway (localhost:18789)
```

## Code Style Guidelines

### OpenTofu/HCL

**Formatting & Naming:**
- Run `tofu fmt -recursive` before every commit
- Use snake_case for all variables, resources, and data source names
- Use descriptive resource names: `hcloud_firewall` not `fw`
- Organize resources: imports → data sources → resources → outputs

**Variable & Output Documentation:**
- Add `description` to every variable (required, not optional)
- Add `description` to every output (required, not optional)
- Include type hints and validation where appropriate

**Structure:**
```hcl
# Section comments use # ==== ====
# ============================================
# Section Name
# ============================================

# Resource comments explain purpose
resource "hcloud_firewall" "main" {
  name = "${var.project_name}-${var.environment}-firewall"
  # ...
}
```

**Comments:**
- Use section dividers (see example above) for logical groups
- Add inline comments for non-obvious firewall rules, cloud-init logic
- Avoid over-commenting obvious code

**Best Practices:**
- Use `dynamic` blocks for repeated rule patterns (see firewall rules in modules/hetzner-vps/main.tf)
- Use variables for all configurable values
- Keep modules focused on single responsibility (e.g., hetzner-vps module only handles VPS provisioning)
- OpenTofu is 100% compatible with Terraform HCL syntax
- No provider changes needed; hcloud provider works identically

### Shell Scripts

**Headers & Shebang:**
```bash
#!/bin/bash
# =============================================================================
# Script Name
# =============================================================================
# Purpose: Brief description
# Usage: ./script.sh [ARGS]
#
# What the script does (bullet list)
# =============================================================================

set -euo pipefail  # Must be at top
```

**Style (Google Shell Style Guide):**
- Use snake_case for function and variable names
- Quote all variable expansions: `"${VAR}"` not `$VAR`
- Use readonly for constants: `readonly CONSTANT_NAME="value"`
- Validate inputs early; exit with `exit 1` on errors
- Use `echo "Error: message" >&2` for error messages

**Error Handling:**
```bash
# Check for required variables
if [[ -z "$REQUIRED_VAR" ]]; then
    echo "Error: REQUIRED_VAR not set" >&2
    exit 1
fi

# Use || for simple fallbacks
VALUE="${OPTIONAL_VAR:-default_value}"

# Validate file existence
if [[ ! -f "$FILE_PATH" ]]; then
    echo "Error: File not found: $FILE_PATH" >&2
    exit 1
fi
```

**Functions:**
- Declare functions before use
- Return 0 on success, 1 on failure
- Use `local` for all function variables
- Add comments explaining purpose and parameters

**Testing:**
```bash
shellcheck deploy/*.sh scripts/*.sh  # Test all scripts
bash -n script.sh                     # Check syntax only
```

### Imports & Dependencies

**OpenTofu:**
- Declare all required providers in `versions.tf`
- Use specific provider versions with `~> X.Y` constraint (e.g., `~> 1.45`)
- Keep provider requirements at module level, not repeated in every file

**Shell:**
- Only use standard utilities (bash built-ins, common Unix tools)
- Avoid external dependencies not pre-installed (Docker, jq, etc.)
- If external tools required, document in CONTRIBUTING.md

### Naming Conventions

**OpenTofu Resources:**
- VPS resource: `hcloud_server` named `main`
- Firewall: named with `${var.project_name}-${var.environment}-firewall`
- SSH key: `hcloud_ssh_key` named `main`
- Keep names consistent across environments

**Variables:**
- Use plural for lists: `ssh_allowed_cidrs` (not `ssh_allowed_cidr`)
- Use `var_` prefix in scripts when referencing OpenTofu vars
- Environment variables in UPPER_CASE: `HCLOUD_TOKEN`, `CONFIG_DIR`

**Shell Variables:**
- Global: UPPERCASE
- Local: snake_case
- Use meaningful names: `TOFU_DIR` not `TF_DIR`

### Error Handling

**OpenTofu:**
- Validate variable types and constraints in `variables.tf`
- Use `sensitive = true` for secrets in variable definitions
- Document required vs optional in descriptions

**Shell:**
- Always use `set -euo pipefail` (exit on error, undefined vars, pipe failures)
- Validate critical variables at start of script
- Provide helpful error messages that include context (file paths, values)
- Use exit codes: 0 (success), 1 (general error), 2 (misuse)
- Example: `[[ -f "$FILE" ]] || { echo "Error: $FILE not found"; exit 1; }`

## Git & Commits

**Commit Message Format (Conventional Commits):**
```
feat: add support for custom firewall rules
fix: correct cloud-init user data template
docs: improve quick start guide
chore: update Terraform provider version
refactor: simplify firewall rule logic
test: add validation for SSH CIDR blocks
```

**Pre-commit Checklist:**
1. Run `make validate` and fix any errors
2. Run `make fmt` to auto-format
3. Test changes: `make plan` for OpenTofu, or manually test scripts
4. Use present tense and imperative mood ("Add" not "Added")
5. Reference issues when relevant: `feat: add feature (closes #123)`

## File Organization

```
infra/terraform/
├── globals/          # Shared configuration (versions, backend)
├── envs/prod/        # Environment-specific (main.tf, variables.tf)
└── modules/          # Reusable modules (each module self-contained)

deploy/              # Deployment scripts (one per operation)
scripts/             # Utility scripts (helper functions, auth setup)
config/              # Configuration templates (inputs.example.sh)
secrets/             # Secret templates (.gitignored)
```

## Key Files & Purpose

- `Makefile` - Primary interface; all commands start with `make`
- `infra/terraform/envs/prod/main.tf` - Environment entry point
- `deploy/bootstrap.sh` - Initial setup (run once after tofu apply)
- `deploy/deploy.sh` - Continuous deployment (pull latest image)
- `.gitignore` - Explicitly excludes `config/inputs.sh`, `secrets/`

## Common Workflows

**Adding a feature:**
1. Create a new resource in appropriate module
2. Run `make fmt && make validate`
3. Test with `make plan`
4. Commit with `feat: <description>`

**Fixing a bug:**
1. Identify root cause (OpenTofu config or script)
2. Update affected file(s)
3. Run `make validate` to confirm syntax
4. Commit with `fix: <description>`

**Updating documentation:**
1. Edit README.md, CONTRIBUTING.md, or inline comments
2. No validation needed for docs-only changes
3. Commit with `docs: <description>`
