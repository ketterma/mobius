# Context-Aware Dashboard & Alert System Design

## Vision

A dynamic, context-aware Home Assistant dashboard that surfaces relevant information based on current home state. Instead of static pages, the interface adapts to show what matters right now - alerts, active devices, and actionable controls.

### Core Principles

1. **Priority-driven**: Critical alerts surface first, routine status fades to background
2. **Context-aware**: Show controls relevant to current activity (music playing → show remote)
3. **Ambient notifications**: Inovelli LEDs provide passive status without phone dependency
4. **Physical confirmation**: NFC tags for low-friction task completion
5. **Conversational**: LLM interface to query home state naturally

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Dashboard Layer                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ Alert Queue │  │ Room Views  │  │ Floor Plan  │      │
│  │ (dynamic)   │  │ (context)   │  │ (status)    │      │
│  └─────────────┘  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                   Notification Layer                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ Mobile Push │  │ Inovelli LED│  │ Browser Mod │      │
│  │ Actionable  │  │ Ambient     │  │ Popups      │      │
│  └─────────────┘  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                  Foundation Layer                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ Alert Queue │  │ Task System │  │ Priority    │      │
│  │ (sensors)   │  │ (Vikunja)   │  │ Manager     │      │
│  └─────────────┘  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────────────────────┘
```

---

## Component Selection

### HACS Integrations (Install These)

| Component | Purpose | Priority |
|-----------|---------|----------|
| **Vikunja HA Integration** | Task management via `todo.*` entities | High |
| **auto-entities** | Dynamic entity lists with filtering | High |
| **Mushroom Cards** | Modern card design with templates | High |
| **card-mod** | CSS styling for state-based colors | High |
| **Browser Mod** | Event-triggered popups | Medium |
| **button-card** | Advanced custom buttons (optional) | Low |

### External Services

- **Vikunja** - Self-hosted task management at `https://tasks.jaxon.cloud`
  - API-driven task creation and management
  - Recurring tasks with flexible scheduling
  - Creates `todo.*` entities in Home Assistant via HACS integration

### Native Integrations

- **Local To-Do** - Ad-hoc task list
- **alert:** - Simple state-based notifications
- **template:** - Custom sensors for alert states

### Future Additions

- **Extended OpenAI Conversation** or **Home-LLM** - Chat interface
- **ha-floorplan** - Advanced floor plan (if SVG approach preferred)

---

## Foundation Layer: Alert & Task System

### Alert Priority System

Single source of truth for what notification should be active:

```yaml
# helpers/alert_priority.yaml
input_select:
  home_alert_priority:
    name: "Home Alert Priority"
    options:
      - none
      - info
      - warning
      - critical
    initial: none
    icon: mdi:alert-circle
```

### Alert Categories & Examples

| Category | Priority | Color | Effect | Examples |
|----------|----------|-------|--------|----------|
| **Security** | Critical | Red (0) | Siren | Door unlocked 5+ min, motion when away |
| **Safety** | Critical | Red (0) | Fast Blink | Water leak, smoke detected |
| **Attention** | Warning | Orange (21) | Pulse | Door/window open, laundry done |
| **Tasks** | Warning | Yellow (42) | Slow Blink | Litter box due, plant dry |
| **Info** | Info | Blue (170) | Solid | Package delivered, guest arrived |
| **Appliance** | Info | Green (85) | Pulse | Washer done, vacuum complete |

### Template Sensors for Alert States

```yaml
# templates/alerts.yaml
template:
  - binary_sensor:
      # Aggregate alert sensors
      - name: "Any Critical Alert"
        unique_id: any_critical_alert
        device_class: problem
        state: >
          {{ is_state('binary_sensor.water_leak', 'on') or
             is_state('lock.front_door', 'unlocked') and
             (now() - states.lock.front_door.last_changed).total_seconds() > 300 }}

      - name: "Any Door Open"
        unique_id: any_door_open
        device_class: door
        state: >
          {{ is_state('binary_sensor.front_door_opening', 'on') or
             is_state('binary_sensor.living_room_door_opening', 'on') or
             is_state('binary_sensor.back_door_door', 'on') }}

      - name: "Any Plant Dry"
        unique_id: any_plant_dry
        device_class: problem
        state: >
          {{ states('sensor.living_room_plant_moisture') | int < 20 }}

      - name: "Pet Water Low"
        unique_id: pet_water_low
        device_class: problem
        state: >
          {{ is_state('binary_sensor.eversweet_3_pro_water_lack_warning', 'on') or
             is_state('binary_sensor.eversweet_max_2_water_lack_warning', 'on') }}

  - sensor:
      - name: "Active Alert Count"
        unique_id: active_alert_count
        state: >
          {{ states.binary_sensor
             | selectattr('attributes.device_class', 'eq', 'problem')
             | selectattr('state', 'eq', 'on')
             | list | count }}
```

### Task System with Vikunja

**Recurring tasks** managed by Vikunja at `https://tasks.jaxon.cloud`:

| Task | Interval | Clear Method |
|------|----------|--------------|
| Clean litter box | Every 1 day | NFC tag scan |
| Water plants | Every 3 days | Moisture sensor auto-clear |
| Replace HVAC filter | Every 90 days | NFC tag scan |
| Check smoke detectors | Every 30 days | Manual dismiss |

**How it works**:
- Tasks created in Vikunja with recurring schedules
- HACS integration (`joeShuff/vikunja-homeassistant`) creates `todo.*` entities
- Complete tasks via `todo.update_item` service
- Recurring tasks auto-reset when completed

**Entity pattern**:
```yaml
# Vikunja creates todo entities per project:
# - todo.household_chores (list of tasks)

# Complete a task:
service: todo.update_item
target:
  entity_id: todo.household_chores
data:
  item: "Clean litter box"
  status: "completed"
```

### NFC Tag Clearing

```yaml
# automations/nfc_task_clear.yaml
automation:
  - id: nfc_clear_litter_box
    alias: "NFC: Clear Litter Box Task"
    trigger:
      - platform: tag
        tag_id: "litter-box-nfc-tag-id"
    action:
      - service: todo.update_item
        target:
          entity_id: todo.household_chores
        data:
          item: "Clean litter box"
          status: "completed"
      - service: notify.mobile_app_jax_iphone
        data:
          message: "Litter box task cleared"
          data:
            tag: "chore-litter-box"
```

---

## Notification Layer: Inovelli LEDs

### LED Color Scheme

Consistent across all 7 switches:

| State | Hue | Effect | Brightness | Duration |
|-------|-----|--------|------------|----------|
| Critical | 0 (Red) | Siren | 100% | Indefinite |
| Warning | 21 (Orange) | Pulse | 80% | Indefinite |
| Task Due | 42 (Yellow) | Slow Blink | 70% | Indefinite |
| Info | 170 (Blue) | Solid | 60% | 5 min |
| Complete | 85 (Green) | Pulse | 80% | 2 min |
| Clear | - | Off | - | - |

### Priority-Based LED Automation

```yaml
# automations/inovelli_priority_display.yaml
automation:
  - id: inovelli_display_priority
    alias: "Inovelli: Display Current Priority"
    trigger:
      - platform: state
        entity_id: input_select.home_alert_priority
    action:
      - choose:
          - conditions:
              - condition: state
                entity_id: input_select.home_alert_priority
                state: "critical"
            sequence:
              - service: zha.issue_zigbee_cluster_command
                data:
                  ieee: "{{ state_attr('light.bedroom_door', 'ieee') }}"
                  endpoint_id: 1
                  cluster_id: 64561
                  cluster_type: in
                  command: 1
                  command_type: server
                  manufacturer: 4655
                  params:
                    effect: "Siren"
                    color: 0
                    level: 100
                    duration: 255

          - conditions:
              - condition: state
                entity_id: input_select.home_alert_priority
                state: "warning"
            sequence:
              - service: zha.issue_zigbee_cluster_command
                data:
                  ieee: "{{ state_attr('light.bedroom_door', 'ieee') }}"
                  endpoint_id: 1
                  cluster_id: 64561
                  cluster_type: in
                  command: 1
                  command_type: server
                  manufacturer: 4655
                  params:
                    effect: "Pulse"
                    color: 21
                    level: 80
                    duration: 255

          - conditions:
              - condition: state
                entity_id: input_select.home_alert_priority
                state: "none"
            sequence:
              - service: zha.issue_zigbee_cluster_command
                data:
                  ieee: "{{ state_attr('light.bedroom_door', 'ieee') }}"
                  endpoint_id: 1
                  cluster_id: 64561
                  cluster_type: in
                  command: 1
                  command_type: server
                  manufacturer: 4655
                  params:
                    effect: "Off"
                    duration: 0

  # Night mode - reduce brightness
  - id: inovelli_night_mode
    alias: "Inovelli: Night Mode Brightness"
    trigger:
      - platform: time
        at: "23:00:00"
    action:
      - service: number.set_value
        target:
          entity_id:
            - number.bedroom_door_default_all_led_on_intensity
            - number.bedroom_default_all_led_on_intensity
            # ... all switch LED intensity entities
        data:
          value: 10
```

### Switch IEEE Addresses

Document these for automation use:

| Switch | Location | IEEE Address |
|--------|----------|--------------|
| Water Closet | Main Bathroom | `TBD` |
| Main Bathroom | Main Bathroom | `TBD` |
| Main Bathroom Perifo | Main Bathroom | `TBD` |
| Main Bedroom Primary | Main Bedroom | `TBD` |
| Main Bedroom Secondary | Main Bedroom | `TBD` |
| Main Closet | Main Closet | `TBD` |
| Bedroom Door | Main Bedroom Entry | `TBD` |

**To find IEEE**: Developer Tools → Events → Listen to `zha_event` → press switch button

---

## Dashboard Layer: Sections View

### Structure

```yaml
# dashboards/home.yaml
title: Home
views:
  - title: Home
    type: sections
    path: home
    icon: mdi:home
    max_columns: 3
    sections:
      # 1. Alert Queue (always first)
      # 2. Quick Actions
      # 3. Active Media (conditional)
      # 4. Climate
      # 5. Room sections...
```

### Section 1: Alert Queue (Dynamic)

```yaml
# Alert queue section
- type: grid
  cards:
    - type: custom:mushroom-title-card
      title: "{{ states('sensor.active_alert_count') }} Active Alerts"
      subtitle: "Tap to dismiss or resolve"

    # Dynamic list of active alerts
    - type: custom:auto-entities
      card:
        type: entities
      filter:
        include:
          - domain: binary_sensor
            device_class: problem
            state: "on"
          - domain: binary_sensor
            device_class: door
            state: "on"
        exclude:
          - entity_id: "*_battery*"
      sort:
        method: last_changed
        reverse: true
      show_empty: false

    # Tasks due
    - type: custom:auto-entities
      card:
        type: entities
        title: Tasks Due
      filter:
        include:
          - domain: sensor
            entity_id: "*chore*"
            state: "<= 0"
      show_empty: false
```

### Section 2: Active Media (Conditional)

```yaml
# Only show when media is playing
- type: grid
  cards:
    - type: conditional
      conditions:
        - entity: media_player.living_room_tv
          state_not: "off"
      card:
        type: custom:mushroom-media-player-card
        entity: media_player.living_room_tv
        use_media_info: true
        show_volume_level: true
        volume_controls:
          - volume_mute
          - volume_set
          - volume_buttons

    - type: conditional
      conditions:
        - entity: media_player.living_room_soundbar
          state_not: "off"
      card:
        type: custom:mushroom-media-player-card
        entity: media_player.living_room_soundbar
```

### Section 3: Room with Context

```yaml
# Living Room section
- type: grid
  cards:
    - type: custom:mushroom-title-card
      title: Living Room

    # Status chips (alerts for this room)
    - type: custom:mushroom-chips-card
      chips:
        - type: conditional
          conditions:
            - entity: binary_sensor.living_room_door_opening
              state: "on"
          chip:
            type: entity
            entity: binary_sensor.living_room_door_opening
            icon_color: orange

        - type: conditional
          conditions:
            - entity: binary_sensor.living_room_plant_dry
              state: "on"
          chip:
            type: template
            icon: mdi:flower-outline
            icon_color: red
            content: "Plant dry"

    # Light controls
    - type: tile
      entity: light.lr_down
      features:
        - type: light-brightness

    - type: tile
      entity: light.lr_tv_strip
      features:
        - type: light-brightness
        - type: light-color-temp
```

### Section 4: Hot Tub (Conditional)

```yaml
# Only show when hot tub is active
- type: grid
  visibility:
    - condition: numeric_state
      entity: climate.hot_tub_temperature
      above: 90
  cards:
    - type: custom:mushroom-title-card
      title: Hot Tub

    - type: custom:mushroom-climate-card
      entity: climate.hot_tub_temperature

    - type: horizontal-stack
      cards:
        - type: tile
          entity: fan.hot_tub_jets_1
          name: Jets 1
        - type: tile
          entity: fan.hot_tub_jets_2
          name: Jets 2

    - type: tile
      entity: light.spa_led
```

---

## Browser Mod: Event Popups

### Doorbell Alert

```yaml
# automations/browser_mod_doorbell.yaml
automation:
  - id: doorbell_popup
    alias: "Browser Mod: Doorbell Popup"
    trigger:
      - platform: state
        entity_id: binary_sensor.g4_doorbell_doorbell
        to: "on"
    action:
      - service: browser_mod.popup
        data:
          title: "Doorbell"
          size: wide
          card:
            type: vertical-stack
            cards:
              - type: picture-glance
                title: Front Door
                camera_image: camera.g4_doorbell_high
                entities:
                  - lock.sense_pro
                  - light.front_porch_1
          # Target specific browsers (kitchen tablet, etc.)
          # browser_id: kitchen_tablet
```

### Person Detected (Camera)

```yaml
automation:
  - id: person_detected_popup
    alias: "Browser Mod: Person Detected"
    trigger:
      - platform: state
        entity_id: binary_sensor.g4_doorbell_person_detected
        to: "on"
    condition:
      - condition: state
        entity_id: person.jax
        state: "home"
    action:
      - service: browser_mod.popup
        data:
          title: "Person at Door"
          card:
            type: picture-entity
            entity: camera.g4_doorbell_high
            camera_view: live
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [x] Deploy Vikunja task management (`https://tasks.jaxon.cloud`)
- [ ] Install HACS components (Vikunja integration, auto-entities, Mushroom, card-mod)
- [ ] Create first user in Vikunja and set up "Household Chores" project
- [ ] Create `input_select.home_alert_priority` helper
- [ ] Create template sensors for alert aggregation
- [ ] Document Inovelli switch IEEE addresses
- [ ] Set up 3-5 initial recurring tasks in Vikunja

### Phase 2: Notifications (Week 2)
- [ ] Create priority-based Inovelli LED automation
- [ ] Add night mode brightness reduction
- [ ] Set up mobile actionable notifications
- [ ] Install NFC tags for task clearing
- [ ] Create NFC → Vikunja `todo.update_item` automations

### Phase 3: Dashboard (Week 3)
- [ ] Create sections-view dashboard structure
- [ ] Add dynamic alert queue section
- [ ] Add conditional media player cards
- [ ] Create room sections with context chips
- [ ] Add conditional hot tub/appliance sections

### Phase 4: Enhancements (Week 4+)
- [ ] Install Browser Mod for popups
- [ ] Create doorbell/person detection popups
- [ ] Add floor plan view (picture-elements)
- [ ] Explore LLM chat integration

---

## File Organization

```
homeassistant/
├── configuration.yaml
├── automations/
│   ├── alerts/
│   │   ├── priority_manager.yaml
│   │   ├── door_alerts.yaml
│   │   └── appliance_alerts.yaml
│   ├── inovelli/
│   │   ├── led_priority_display.yaml
│   │   └── night_mode.yaml
│   ├── nfc/
│   │   └── task_clearing.yaml
│   └── browser_mod/
│       └── popups.yaml
├── templates/
│   └── alerts.yaml
├── helpers/
│   └── alert_priority.yaml
├── dashboards/
│   └── home.yaml
└── docs/
    ├── context-aware-dashboard-design.md  # This file
    └── ...
```

---

## Open Questions

1. **LLM choice**: Extended OpenAI Conversation vs Home-LLM (local)?
2. **Floor plan source**: Do you have a floor plan image, or need to create one?
3. **Tablet placement**: Wall-mounted tablets for dedicated dashboard views?
4. **Family adoption**: Should tasks have user assignment (KidsChores)?

---

## References

- [Vikunja](https://vikunja.io/) - Self-hosted task management
- [Vikunja HA Integration](https://github.com/joeShuff/vikunja-homeassistant) - HACS integration
- [auto-entities](https://github.com/thomasloven/lovelace-auto-entities)
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom)
- [card-mod](https://github.com/thomasloven/lovelace-card-mod)
- [Browser Mod](https://github.com/thomasloven/hass-browser_mod)
- [Inovelli LED Calculator](https://nathanfiscus.github.io/inovelli-notification-calc/)
