# Migration Guide: Terraform to OpenTofu

This guide helps you migrate from Terraform to OpenTofu for this project.

## Why OpenTofu?

In August 2023, HashiCorp changed Terraform's license from MPL 2.0 to BSL 1.1, restricting commercial use. OpenTofu is a community-driven, open-source fork maintained by the Linux Foundation that:

- Uses the open Mozilla Public License 2.0 (MPL 2.0)
- Is 100% compatible with Terraform 1.5.x HCL
- Supports all existing Hetzner Cloud modules
- Maintains long-term stability without vendor lock-in

## Prerequisites

- OpenTofu >= 1.8 ([Installation Guide](https://opentofu.org/docs/intro/install/))
- Existing Terraform state file (backed up)
- Current infrastructure deployed with Terraform

## Migration Steps

### Step 0: Backup Everything

**Critical:** Always back up your state before migration.

```bash
# Local state backup
cp infra/terraform/envs/prod/terraform.tfstate infra/terraform/envs/prod/terraform.tfstate.backup

# Remote S3 backend backup
aws s3 cp s3://openclaw-tfstate/prod/terraform.tfstate ./terraform.tfstate.backup \
  --endpoint-url https://s3.hetzner.cloud
```

### Step 1: Verify Current State is Clean

```bash
source config/inputs.sh
make plan
```

Should show: **No changes. Your infrastructure matches the configuration.**

If there are pending changes, apply them first:
```bash
make apply
```

### Step 2: Install OpenTofu

**macOS with Homebrew:**
```bash
brew install opentofu
tofu --version  # Should show: OpenTofu v1.8.x or later
```

**Linux:**
```bash
curl --proto '=https' --tlsv1.2 -fsSL https://opentofu.org/install.sh | sh
tofu --version
```

**Windows:**
```powershell
choco install opentofu
tofu --version
```

See [OpenTofu Installation](https://opentofu.org/docs/intro/install/) for other platforms.

### Step 3: Test OpenTofu Commands

Ensure `tofu` works as a drop-in replacement:

```bash
source config/inputs.sh
cd infra/terraform/envs/prod

# Reinitialize with OpenTofu
tofu init

# Should match Terraform output
tofu plan

# Should show: No changes
```

### Step 4: Upgrade Your State (if needed)

For the first `tofu apply`, your state file is automatically upgraded to OpenTofu format:

```bash
tofu apply
```

**Output should show:** Apply complete! (0 added, 0 changed, 0 destroyed)

### Step 5: Use OpenTofu Commands

Replace all `terraform` commands with `tofu`:

```bash
# Old way (Terraform)
terraform init
terraform plan
terraform apply

# New way (OpenTofu)
tofu init
tofu plan
tofu apply
```

Or use the Makefile (commands remain the same):
```bash
make init
make plan
make apply
```

## Special Notes

### S3 Backend Configuration

If using Hetzner Object Storage for state:

1. OpenTofu uses the same S3 backend configuration as Terraform
2. No changes needed to `infra/terraform/envs/prod/main.tf`
3. Ensure AWS credentials are set:
   ```bash
   export AWS_ACCESS_KEY_ID=<your-access-key>
   export AWS_SECRET_ACCESS_KEY=<your-secret-key>
   # Or source config/inputs.sh
   ```

### Provider Compatibility

The Hetzner Cloud provider (`hetznercloud/hcloud ~> 1.45`) works identically in OpenTofu:
- No provider changes needed
- All resources work the same way
- No HCL syntax changes required

### Development Variables

Scripts may reference Terraform variables. All `TF_VAR_*` environment variables work with OpenTofu:

```bash
# These work in both Terraform and OpenTofu
export TF_VAR_ssh_key_fingerprint="aa:bb:cc:..."
export TF_VAR_environment="prod"
```

## Troubleshooting

### "command not found: tofu"

OpenTofu is not installed. See **Step 2** for installation instructions.

### "Error: Resource already managed"

This can happen if state files got out of sync. Solution:

```bash
# Use backup to restore if needed
cp terraform.tfstate.backup terraform.tfstate
tofu init
tofu plan  # Should show no changes
```

### "Error: Backend initialization failed"

S3 credentials not set. Solution:

```bash
source config/inputs.sh
make init
```

### Mixed Terraform/OpenTofu State

If both tools were used on the same infrastructure:

1. Stick with OpenTofu going forward
2. Run `tofu init` to reinitialize
3. Run `tofu plan` to verify state consistency
4. Keep Terraform uninstalled locally to avoid accidents

## Verification

After migration, verify everything works:

```bash
# Check OpenTofu version
tofu --version

# Test full workflow
source config/inputs.sh
make init && make plan

# Verify deployment still works
make bootstrap
make deploy
make status
```

## Rollback

If you need to rollback to Terraform (not recommended):

1. Keep your `terraform.tfstate.backup` file
2. Install Terraform >= 1.5
3. Restore state: `cp terraform.tfstate.backup terraform.tfstate`
4. Run `terraform init`

Note: OpenTofu states can be read by Terraform, but Terraform-created state may need adjustment for OpenTofu.

## Questions?

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [OpenTofu GitHub](https://github.com/opentofu/opentofu)
- [OpenTofu Migration Guide (Terraform 1.8.x)](https://opentofu.org/docs/v1.9/intro/migration/terraform-1.8/)

## References

[timderzhavets.com - Migrating from Terraform to OpenTofu](https://timderzhavets.com/blog/migrating-from-terraform-to-opentofu-a-practical-guide/)

[scalr.com - Migrating from Terraform to OpenTofu](https://scalr.com/learning-center/migrating-from-terraform-to-opentofu/)

[opentofu.org - Migration Guide](https://opentofu.org/docs/v1.9/intro/migration/terraform-1.8/)
