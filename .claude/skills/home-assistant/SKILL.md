---
name: home-assistant
description: "MUST USE THIS SKILL when accessing Home Assistant via API. Home Assistant automation, REST API, Supervisor API, hass-cli, service calls, triggers, conditions, actions, blueprints, Inovelli LED, Hue scenes, WLED effects. Use for creating automations, calling services, managing devices."
---

# Home Assistant

## Quick Start

### hass-cli Setup

Use `uv run` with the `.env` file in the homelab repo:

```bash
# Shorthand alias (optional)
alias hass='uv run --with homeassistant-cli --env-file .env hass-cli'

# List areas (use for room-based control)
hass area list

# List entities (find correct entity IDs)
hass entity list light
hass entity list | grep -i kitchen

# Get entity state
hass -o yaml state get sensor.temperature
```

### Service Calls

Use `raw post` for all service calls (supports area_id, multiple entities, complex data):

```bash
# Turn off all lights in an area
hass raw post /api/services/light/turn_off --json '{"area_id": "living_room"}'

# Turn on with brightness
hass raw post /api/services/light/turn_on --json '{"area_id": "kitchen", "brightness_pct": 80}'

# Single entity
hass raw post /api/services/light/turn_on --json '{"entity_id": "light.desk_lamp", "brightness": 200}'

# Multiple entities
hass raw post /api/services/light/turn_off --json '{"entity_id": ["light.kitchen", "light.hallway"]}'

# Fire custom event
hass raw post /api/events/my_custom_event --json '{"key": "value"}'
```

**Note**: `service call --arguments` only works for simple `key=value` pairs. Use `raw post` for area targeting and complex data.

### Workflow for Room Control

1. `hass area list` - find area ID (e.g., `living_room`, `kitchen`)
2. `hass raw post /api/services/<domain>/<service> --json '{"area_id": "..."}'`

### Time Zones

**Important**: All timestamps from the API are in UTC. Convert to user's local time when displaying:
- `last_changed`, `last_updated`, `last_reported` are all UTC
- Get local offset with `date +%z` (e.g., `-0800` = UTC-8)
- Convert UTC to local before showing times to user

### Camera Snapshots

```bash
# List cameras
hass entity list camera

# Fetch snapshot
source .env && ./scripts/ha-snapshot.sh camera.g4_doorbell_high
# Saves to /tmp/g4_doorbell_high_<timestamp>.jpg

# Specify output path
source .env && ./scripts/ha-snapshot.sh camera.living_room_high /tmp/snapshot.jpg
```

Create long-lived tokens at: `http://your-ha:8123/profile/security`

## Automation Structure

Modern syntax uses **plural keys**: `triggers`, `conditions`, `actions`

```yaml
automation:
  - id: "motion_light"
    alias: "Motion-activated light"
    mode: restart  # single|restart|queued|parallel

    triggers:
      - trigger: state
        entity_id: binary_sensor.motion
        to: "on"
        id: motion_on

    conditions:
      - condition: sun
        after: sunset

    actions:
      - action: light.turn_on
        target:
          entity_id: light.hallway
        data:
          brightness_pct: 80
      - wait_for_trigger:
          - trigger: state
            entity_id: binary_sensor.motion
            to: "off"
      - delay: "00:02:00"
      - action: light.turn_off
        target:
          entity_id: light.hallway
```

### Trigger Types

| Type | Example |
|------|---------|
| `state` | `to: "on"`, `for: minutes: 5` |
| `numeric_state` | `above: 25`, `below: 30` |
| `time` | `at: "08:00:00"` |
| `time_pattern` | `minutes: "/5"` (every 5 min) |
| `sun` | `event: sunset`, `offset: "-01:00:00"` |
| `event` | `event_type: my_event` |
| `webhook` | `webhook_id: my-hook` |
| `template` | `value_template: "{{ condition }}"` |

### Conditional Actions

```yaml
actions:
  - if:
      - condition: state
        entity_id: input_boolean.night_mode
        state: "on"
    then:
      - action: light.turn_on
        data:
          brightness: 50
    else:
      - action: light.turn_on
        data:
          brightness: 255
```

### Choose (Multiple Branches)

```yaml
actions:
  - choose:
      - conditions:
          - condition: trigger
            id: motion_on
        sequence:
          - action: light.turn_on
      - conditions:
          - condition: trigger
            id: timer_end
        sequence:
          - action: light.turn_off
    default:
      - action: notify.mobile_app
        data:
          message: "Unknown trigger"
```

## Blueprint Structure

```yaml
blueprint:
  name: "Motion Light"
  description: "Turn on light when motion detected"
  domain: automation
  input:
    motion_sensor:
      name: "Motion Sensor"
      selector:
        entity:
          filter:
            domain: binary_sensor
            device_class: motion

    target_light:
      name: "Light"
      selector:
        target:
          entity:
            domain: light

    delay_seconds:
      name: "Off Delay"
      default: 120
      selector:
        number:
          min: 0
          max: 600
          unit_of_measurement: seconds

triggers:
  - trigger: state
    entity_id: !input motion_sensor
    to: "on"

actions:
  - action: light.turn_on
    target: !input target_light
  - delay:
      seconds: !input delay_seconds
  - action: light.turn_off
    target: !input target_light

mode: restart
```

**Important**: To use `!input` in templates, assign to variable first:
```yaml
variables:
  my_input: !input my_input
actions:
  - action: notify.mobile_app
    data:
      message: "Value: {{ my_input }}"
```

## Device-Specific Patterns

### Inovelli LED Notifications

See `devices/inovelli.md` for full reference.

```yaml
# Set LED notification (Z-Wave JS)
action: zwave_js.bulk_set_partial_config_parameters
data:
  parameter: "16"  # Dimmer; use "8" for switch
  value: 83823268  # Use calculator below
target:
  device_id: YOUR_DEVICE_ID
```

**LED Calculator**: https://nathanfiscus.github.io/inovelli-notification-calc/

### Hue Scenes

See `devices/hue.md` for full reference.

```yaml
action: hue.activate_scene
data:
  entity_id: scene.hue_living_room_relax
  transition: 2
  dynamic: true  # For dynamic scenes
```

### WLED Effects

See `devices/wled.md` for full reference.

```yaml
# Turn on and set preset
- action: light.turn_on
  target:
    entity_id: light.wled
- action: select.select_option
  target:
    entity_id: select.wled_preset
  data:
    option: "Rainbow"
```

## Supervisor API

For addon management, use Supervisor API (different from REST API).

**From within HA or addon** (uses `SUPERVISOR_TOKEN`):
```bash
curl -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  http://supervisor/addons/core_git_pull/info
```

**External access** requires Remote API proxy addon:
1. Install from: `https://github.com/home-assistant/addons-development`
2. Get token from addon logs
3. Access at `http://192.168.64.2:80/` with Bearer token

Common endpoints:
- `GET /addons` - List addons
- `POST /addons/<addon>/start` - Start addon
- `POST /addons/<addon>/restart` - Restart addon
- `GET /addons/<addon>/logs` - Get logs

## SSH Access (HAOS)

**Important**: SSH to a Home Assistant OS instance connects to the SSH **addon container**, not the HAOS host.

You have access to:
- `ha` CLI for addon/system management
- `/config` directory (HA configuration)
- Network access to other services

You do NOT have:
- Direct access to `/mnt/data/supervisor/` or other addons' data
- Root access to the HAOS filesystem

For direct HAOS filesystem access (e.g., reading other addons' data), you need to access the underlying hypervisor/host.

## Reference Files

- `reference/api.md` - Full REST API endpoint reference
- `reference/supervisor-api.md` - Supervisor API for addon management
- `reference/automations.md` - All trigger/condition/action types
- `reference/blueprints.md` - Blueprint selectors and sections
- `devices/inovelli.md` - LED notifications, button events
- `devices/hue.md` - Scenes, groups, entertainment areas
- `devices/wled.md` - Presets, effects, segments

## External Resources

- **REST API**: https://developers.home-assistant.io/docs/api/rest/
- **Automations**: https://www.home-assistant.io/docs/automation/yaml/
- **Blueprints**: https://www.home-assistant.io/docs/blueprint/
- **hass-cli**: https://github.com/home-assistant-ecosystem/home-assistant-cli
