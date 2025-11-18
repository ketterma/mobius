# Home Assistant API Reference

Detailed examples for interacting with Home Assistant via REST API and CLI.

## Authentication

### Long-Lived Access Token
Create in HA UI: Profile → Long-Lived Access Tokens

```bash
# Store in environment
export HASS_TOKEN="your-token-here"

# Or use from .env file
source /Users/jax/Documents/homelab/.env
```

### Supervisor API Token
For addon management, use the Remote API proxy addon:
```bash
# Get token from addon logs
ssh root@192.168.64.2 "ha addons logs 77f1785d_remote_api | grep 'API Key'"
```

## Service Calls

### Light Control
```bash
# Turn on with brightness
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.main_bedroom_lights", "brightness_pct": 75}' \
  http://192.168.64.2:8123/api/services/light/turn_on

# Turn off
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.kitchen_lights"}' \
  http://192.168.64.2:8123/api/services/light/turn_off

# Toggle
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.dymera_lights"}' \
  http://192.168.64.2:8123/api/services/light/toggle
```

### Reload Services
```bash
# Reload light groups (after editing configuration.yaml light section)
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/group/reload

# Reload automations (after editing automations.yaml)
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/automation/reload

# Reload scripts
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/script/reload

# Reload scenes
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/scene/reload

# Reload core config (input_*, template, generic_thermostat, etc.)
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/homeassistant/reload_core_config
```

### Automation Control
```bash
# Trigger an automation
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "automation.main_bathroom_switch"}' \
  http://192.168.64.2:8123/api/services/automation/trigger

# Turn off automation
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "automation.security_lights_activate"}' \
  http://192.168.64.2:8123/api/services/automation/turn_off
```

## State Queries

### Get Entity State
```bash
# Single entity
curl -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/states/light.main_bedroom_lights

# All states (large response)
curl -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/states
```

### Check API Status
```bash
curl -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/
```

## Webhook Triggers

### GitOps Deploy Webhook
```bash
# Trigger git pull addon to update config
curl -X POST http://192.168.64.2:8123/api/webhook/git-pull-deploy
```

## HA CLI Commands (via SSH)

```bash
# SSH to HA
ssh root@192.168.64.2

# Core operations
ha core check              # Validate configuration
ha core info               # Show core info
ha core restart            # Full restart (disruptive!)
ha core update             # Update HA Core

# Addon management
ha addons list             # List all addons
ha addons info core_git_pull
ha addons start core_git_pull
ha addons stop core_git_pull
ha addons restart core_git_pull
ha addons logs core_git_pull

# System info
ha host info
ha network info
ha supervisor info
```

## Device Registry

### Find Device IDs
Device IDs are needed for blueprint automations like Inovelli switches.

```bash
# On HA via SSH
cat /homeassistant/.storage/core.device_registry | jq '.data.devices[] | select(.name | contains("Bedroom"))'

# Or use jq to find by entity
cat /homeassistant/.storage/core.entity_registry | jq '.data.entities[] | select(.entity_id == "light.bathroom")'
```

### Debug ZHA Events
In HA UI: Developer Tools → Events → Listen to events

Enter `zha_event` and click "Start listening", then press a button on the Inovelli switch to see:
```json
{
  "device_id": "0d0e7c87550b66a1c07df4344ce9349e",
  "command": "on",
  "params": {}
}
```

## Supervisor API (Port 80)

Requires Remote API proxy addon.

```bash
# Get addon info
curl -H "Authorization: Bearer <supervisor-token>" \
  http://192.168.64.2:80/addons/core_git_pull/info

# Start addon
curl -X POST -H "Authorization: Bearer <supervisor-token>" \
  http://192.168.64.2:80/addons/core_git_pull/start

# Get all addons
curl -H "Authorization: Bearer <supervisor-token>" \
  http://192.168.64.2:80/addons
```

## Common Patterns

### Add New Inovelli Switch Automation

1. Press switch button and watch `zha_event` in Developer Tools
2. Note the `device_id` from event
3. Identify target light entity (create HA group if needed)
4. Find the switch's on/off transition number entity
5. Add automation to `automations.yaml`:
```yaml
- id: 'unique_id'
  alias: Switch Name
  use_blueprint:
    path: jax/inovelli_hue.yaml
    input:
      controller: <device_id>
      target_light: light.target_group
      onoff_transition_number: number.switch_on_off_transition_time
      switch_level_entity: light.switch_entity
```
6. Reload automations: `curl -X POST ... /api/services/automation/reload`

### Create Light Group

Add to `configuration.yaml`:
```yaml
light:
  - platform: group
    name: My Light Group
    entities:
      - light.hue_light_1
      - light.hue_light_2
```

Then reload: `curl -X POST ... /api/services/group/reload`

The group entity will be `light.my_light_group` (name converted to snake_case).
