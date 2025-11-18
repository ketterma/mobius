---
name: home-assistant-dashboards
description: "Home Assistant dashboard, Lovelace, sections view, tile cards, Mushroom cards, Button-card, YAML dashboards, custom cards, mobile design, themes. Use for creating or modifying HA dashboards."
---

# Home Assistant Dashboards

## Sections View (Modern Default)

The sections view is the modern dashboard layout with drag-and-drop grid organization.

```yaml
views:
  - title: Home
    type: sections
    path: home
    icon: mdi:home
    max_columns: 3
    sections:
      - type: grid
        cards:
          - type: tile
            entity: light.living_room
            features:
              - type: light-brightness
          - type: tile
            entity: climate.thermostat
            features:
              - type: climate-hvac-modes
                hvac_modes: [heat, cool, "off"]
              - type: target-temperature
```

## Tile Cards

The tile card is the primary building block in sections view.

```yaml
type: tile
entity: light.bedroom
name: "Bedroom Light"
icon: mdi:ceiling-light
color: amber  # or hex: "#FFB300"
vertical: false
hide_state: false
state_content:
  - state
  - brightness
features:
  - type: light-brightness
  - type: light-color-temp
```

### Tile Features by Entity Type

**Light:**
```yaml
features:
  - type: light-brightness
  - type: light-color-temp
```

**Climate:**
```yaml
features:
  - type: climate-hvac-modes
    hvac_modes: [auto, heat, cool, "off"]
  - type: target-temperature
  - type: climate-preset-modes
    preset_modes: [home, eco, away]
```

**Cover:**
```yaml
features:
  - type: cover-open-close
  - type: cover-position
  - type: cover-tilt-position
```

**Media Player:**
```yaml
features:
  - type: media-player-volume-slider
```

**Vacuum:**
```yaml
features:
  - type: vacuum-commands
    commands: [start_pause, stop, return_home, locate]
```

**Colors**: `primary`, `accent`, `red`, `pink`, `purple`, `deep-purple`, `indigo`, `blue`, `light-blue`, `cyan`, `teal`, `green`, `light-green`, `lime`, `yellow`, `amber`, `orange`, `deep-orange`, `brown`, `grey`, `blue-grey`

## YAML Mode Setup

For version control, use YAML mode dashboards:

```yaml
# configuration.yaml
lovelace:
  mode: storage  # Keep default dashboard editable
  resources:
    - url: /hacsfiles/lovelace-mushroom/mushroom.js
      type: module
  dashboards:
    lovelace-yaml:
      mode: yaml
      title: Main
      icon: mdi:home
      show_in_sidebar: true
      filename: dashboards/main.yaml
```

**Note**: Once in YAML mode, UI editor is disabled for that dashboard.

## Conditional Visibility

### Per-Card (Modern)

Use the Visibility tab in UI or add conditions:

```yaml
type: tile
entity: light.guest_room
visibility:
  - condition: state
    entity: input_boolean.guest_mode
    state: "on"
```

### Conditional Card

```yaml
type: conditional
conditions:
  - condition: state
    entity: alarm_control_panel.home
    state_not: disarmed
  - condition: screen
    media_query: "(min-width: 768px)"
card:
  type: tile
  entity: binary_sensor.front_door
```

**Condition Types**: `state`, `state_not`, `numeric_state`, `screen`, `user`, `and`, `or`, `not`

## Custom Cards (HACS)

### Mushroom Cards

Clean, minimalist design. Install via HACS.

```yaml
# Room layout
type: vertical-stack
cards:
  - type: custom:mushroom-title-card
    title: Living Room
    subtitle: "{{ states('sensor.temperature') }}°C"

  - type: custom:mushroom-chips-card
    chips:
      - type: entity
        entity: binary_sensor.motion
      - type: weather
        entity: weather.home

  - type: horizontal-stack
    cards:
      - type: custom:mushroom-light-card
        entity: light.ceiling
        use_light_color: true
      - type: custom:mushroom-light-card
        entity: light.lamp
```

**Template card for dynamic content:**
```yaml
type: custom:mushroom-template-card
primary: "{{ states('sensor.temperature') }}°C"
secondary: "Humidity: {{ state_attr('sensor.temperature', 'humidity') }}%"
icon: mdi:thermometer
icon_color: >
  {% if states('sensor.temperature')|float > 25 %}
    red
  {% else %}
    blue
  {% endif %}
tap_action:
  action: more-info
```

### Button-Card

Highly customizable with JavaScript templates.

```yaml
# Define templates at dashboard top
button_card_templates:
  light_button:
    aspect_ratio: 1/1
    show_state: true
    tap_action:
      action: toggle
    styles:
      card:
        - border-radius: 12px
    state:
      - value: "on"
        styles:
          card:
            - background-color: var(--primary-color)

# Use template
type: custom:button-card
template: light_button
entity: light.bedroom
name: Bedroom
icon: mdi:bed
```

### Decluttering Card

Reusable card templates:

```yaml
# Define at dashboard top
decluttering_templates:
  light_tile:
    card:
      type: tile
      entity: "[[entity]]"
      name: "[[name]]"
      features:
        - type: light-brightness

# Use template
cards:
  - type: custom:decluttering-card
    template: light_tile
    variables:
      - entity: light.bedroom
      - name: Bedroom
```

## Mobile-First Design

### Bubble Card (Pop-ups)

Bottom navigation with pop-ups for mobile:

```yaml
type: custom:bubble-card
card_type: pop-up
hash: "#living-room"
name: Living Room
icon: mdi:sofa
```

### Responsive Grid

```yaml
type: grid
columns: 2
square: false
cards:
  - type: tile
    entity: light.one
  - type: tile
    entity: light.two
```

## Complete Dashboard Example

```yaml
# dashboards/main.yaml
title: Home
views:
  - title: Home
    type: sections
    path: home
    icon: mdi:home
    max_columns: 3
    sections:
      # Living Room
      - type: grid
        cards:
          - type: custom:mushroom-title-card
            title: Living Room
          - type: tile
            entity: light.living_room
            features:
              - type: light-brightness
          - type: tile
            entity: climate.living_room
            features:
              - type: climate-hvac-modes
                hvac_modes: [heat, cool, "off"]
              - type: target-temperature

      # Security
      - type: grid
        cards:
          - type: custom:mushroom-title-card
            title: Security
          - type: tile
            entity: alarm_control_panel.home
            features:
              - type: alarm-modes
                modes: [armed_home, armed_away, disarmed]
          - type: tile
            entity: lock.front_door

  - title: Media
    type: sections
    path: media
    icon: mdi:television
    sections:
      - type: grid
        cards:
          - type: tile
            entity: media_player.living_room
            features:
              - type: media-player-volume-slider
```

## Reference Files

- `reference/tile-cards.md` - All tile features by entity type
- `reference/custom-cards.md` - Mushroom, Button-card, Bubble patterns
- `reference/yaml-mode.md` - Version control workflow

## External Resources

- **Dashboards**: https://www.home-assistant.io/dashboards/
- **Sections View**: https://www.home-assistant.io/dashboards/sections/
- **Tile Card**: https://www.home-assistant.io/dashboards/tile/
- **Features**: https://www.home-assistant.io/dashboards/features/
- **Mushroom Cards**: https://github.com/piitaya/lovelace-mushroom
- **Button-Card**: https://github.com/custom-cards/button-card
- **Bubble Card**: https://github.com/Clooos/Bubble-Card
