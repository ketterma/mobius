# Home Assistant Configuration

This is the `homeassistant` orphan branch of the mobius repo, deployed to the HA VM via git pull addon.

## Quick Reference

- **VM:** `192.168.64.2` (IoT VLAN)
- **SSH:** `ssh root@192.168.64.2` (Terminal & SSH addon container)
- **Web UI:** `https://home.jaxon.cloud`
- **API:** Port 8123 with long-lived token (`HASS_TOKEN` in .env)

## Key Files

- `configuration.yaml` - Main config with light groups
- `automations.yaml` - Automations (Inovelli switches, security lights, etc.)
- `blueprints/automation/jax/inovelli_hue.yaml` - Blueprint for Inovelli→Hue control
- `docs/switch-light-inventory.md` - Switch to light mappings with diagrams

## Essential Commands

### Targeted Reloads (avoid full restarts)
```bash
# Reload light groups
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/group/reload

# Reload automations
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/automation/reload

# Reload core config (input_*, template, etc.)
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  http://192.168.64.2:8123/api/services/homeassistant/reload_core_config
```

### Entity Control
```bash
# Turn off a light
curl -X POST -H "Authorization: Bearer $HASS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.kitchen_lights"}' \
  http://192.168.64.2:8123/api/services/light/turn_off
```

### HA CLI (via SSH)
```bash
ha core check          # Validate config
ha core restart        # Full restart (use sparingly)
ha addons logs core_git_pull
```

## Important Notes

### Reload vs Restart
- **Use targeted reloads** for group, automation, script changes
- `ha core restart` is disruptive - only when necessary
- Light platform groups need `group/reload`, not `reload_core_config`

### Inovelli Switch Automations
- Use `jax/inovelli_hue.yaml` blueprint
- Need: device_id (from `zha_event`), target light entity, transition number, switch level entity
- Find device_id by pressing switch and watching Events in Developer Tools

### ZHA Events
- Debug in HA UI: Developer Tools → Events → Listen to `zha_event`
- Device IDs in `/homeassistant/.storage/core.device_registry`

### GitOps Flow
1. Commit to `homeassistant` branch → push
2. Flux alert triggers webhook → `git-pull-deploy`
3. Git pull addon updates `/homeassistant`
4. Manual reload needed for changes to take effect

See `docs/ha-api-reference.md` for detailed API examples.
