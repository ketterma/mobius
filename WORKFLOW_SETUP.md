# Home Assistant Config Validation Setup

This document explains how to set up automated Home Assistant and ESPHome configuration validation using GitHub Actions.

## Setup Instructions

### 1. Move the Workflow File

Due to GitHub App permissions, the workflow file needs to be manually moved to the correct location:

```bash
mkdir -p .github/workflows
mv home-assistant-config-check.yml .github/workflows/
```

### 2. Commit and Push the Workflow

```bash
git add .github/workflows/home-assistant-config-check.yml
git commit -m "Add Home Assistant config validation workflow"
git push
```

## What the Workflow Does

### Home Assistant Validation
- Uses the `frenck/action-home-assistant` GitHub action
- Validates all Home Assistant YAML configuration files
- Checks syntax, component configuration, and dependencies
- Runs on every PR and push to main branch

### ESPHome Validation  
- Uses the official ESPHome CLI
- Creates a temporary secrets file from `esphome/secrets.yaml.example`
- Validates all ESPHome device configurations
- Ensures configs can compile successfully

## Example Secrets File

The workflow uses `esphome/secrets.yaml.example` for validation. This file contains placeholder values for all secrets referenced in your ESPHome configs:

- WiFi credentials
- API keys
- OTA passwords
- Device-specific secrets

## Benefits

✅ **Catch config errors early** - Before they reach your Home Assistant instance
✅ **Consistent validation** - Same validation process across all PRs
✅ **No secrets required** - Uses example file with safe placeholder values
✅ **Parallel validation** - Home Assistant and ESPHome checks run concurrently
✅ **Automatic updates** - Workflow runs on every change to ensure ongoing validity

## Troubleshooting

If validation fails:
1. Check the GitHub Actions logs for specific error messages
2. Ensure all secrets referenced in configs are included in `esphome/secrets.yaml.example`
3. Verify YAML syntax is correct
4. Test ESPHome configs locally with `esphome config <file.yaml>`