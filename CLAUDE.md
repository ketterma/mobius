# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Home Assistant configuration repository that manages a smart home setup. Home Assistant is an open-source platform that allows local control of smart home devices. The configuration includes custom integrations, ESPHome devices, automations, and UI themes.

## File Structure and Architecture

### Core Configuration Files
- `configuration.yaml` - Main Home Assistant configuration file that loads other components
- `automations.yaml` - Home Assistant automations (currently empty)
- `scripts.yaml` - Home Assistant scripts (currently empty)  
- `scenes.yaml` - Home Assistant scenes (currently empty)
- `secrets.yaml` - Contains sensitive configuration values (passwords, API keys)
- `known_devices.yaml` - Device tracking configuration

### Custom Components (`custom_components/`)
Contains third-party integrations that extend Home Assistant functionality:

- **HACS** (`hacs/`) - Home Assistant Community Store for managing custom integrations
- **Hue Sync Box** (`huesyncbox/`) - Philips Hue Sync Box integration
- **LocalTuya** (`localtuya/`) - Local control of Tuya devices without cloud
- **PetKit** (`petkit/`) - PetKit smart pet device integration
- **Rivian** (`rivian/`) - Rivian electric vehicle integration
- **SmartThinQ Sensors** (`smartthinq_sensors/`) - LG appliance integration
- **SPAN Panel** (`span_panel/`) - SPAN electrical panel monitoring
- **Tesla Custom** (`tesla_custom/`) - Enhanced Tesla vehicle integration

### ESPHome Devices (`esphome/`)
Configuration for ESP32/ESP8266 microcontroller devices:
- `hot-tub.yaml` - Hot tub controller using IQ2020 protocol for spa automation
- `ratgdov25i-1bb5f9.yaml` - Garage door controller
- `secrets.yaml` - ESPHome-specific secrets

### UI and Frontend (`www/`, `themes/`)
- `www/` - Static web assets for custom Lovelace cards and resources
- `themes/visionos/` - visionOS-inspired UI themes

### Blueprints (`blueprints/`)
Reusable automation and script templates:
- `automation/homeassistant/motion_light.yaml` - Motion-activated lighting
- `automation/homeassistant/notify_leaving_zone.yaml` - Zone departure notifications
- `script/homeassistant/confirmable_notification.yaml` - Confirmation-based notifications

## Development Commands

Home Assistant doesn't use traditional build/test commands. Instead:

### Configuration Validation
```bash
# Check configuration syntax (if Home Assistant CLI is available)
hass --script check_config

# For ESPHome devices
esphome config hot-tub.yaml
esphome config ratgdov25i-1bb5f9.yaml
```

### ESPHome Development
```bash
# Compile and upload to device
esphome run hot-tub.yaml

# Monitor logs
esphome logs hot-tub.yaml

# Validate configuration
esphome config hot-tub.yaml
```

## Configuration Patterns

### Entity Organization
- Entities are organized by domain (sensor, switch, light, etc.)
- Custom integrations follow Home Assistant's entity model
- Each custom component includes manifest.json with dependencies

### YAML Structure
- Uses `!include` directives to split configuration across files
- Secrets are externalized to `secrets.yaml`
- ESPHome configs are self-contained with embedded secrets

### Custom Integration Architecture
Each custom component follows Home Assistant's integration pattern:
- `__init__.py` - Component initialization and setup
- `config_flow.py` - Configuration UI flow
- `const.py` - Constants and configuration schema
- `coordinator.py` - Data update coordination (if applicable)
- Platform files (`sensor.py`, `switch.py`, etc.) - Entity implementations
- `manifest.json` - Integration metadata and dependencies

## Security Considerations

- Secrets are stored in `secrets.yaml` files - never commit actual secret values
- ESPHome devices have embedded API keys and passwords
- Custom integrations may require API tokens stored in secrets
- Network access is configured through trusted proxies in `configuration.yaml`

## Common Integration Points

- Custom integrations register entities through Home Assistant's entity registry
- ESPHome devices communicate via API with encryption keys
- HACS manages installation and updates of custom integrations
- Blueprints provide reusable automation templates
- Custom UI themes modify the frontend appearance

## Working with This Repository

When modifying configurations:
1. Validate YAML syntax before applying changes
2. Test ESPHome configurations in safe mode before full deployment
3. Use Home Assistant's built-in configuration checker
4. Restart Home Assistant after configuration changes
5. Monitor logs for integration errors or warnings