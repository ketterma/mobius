# WLED

Requires WLED 0.14.0+. Auto-discovered via mDNS.

## Entities Created

- **Lights**: Master + per-segment
- **Selects**: Preset, Playlist, Color palette
- **Numbers**: Intensity, Speed
- **Sensors**: Current draw, Uptime, WiFi signal

## Presets and Effects

Create presets in WLED web interface, then activate from HA:

```yaml
# Activate preset (must turn on first!)
- action: light.turn_on
  target:
    entity_id: light.wled
- action: select.select_option
  target:
    entity_id: select.wled_preset
  data:
    option: "My Preset"  # Use name, not number

# Set effect directly
action: light.turn_on
target:
  entity_id: light.wled
data:
  effect: "Rainbow"

# Random effect
action: light.turn_on
target:
  entity_id: light.wled
data:
  effect: "{{ state_attr('light.wled', 'effect_list') | random }}"
```

## Full Effect Configuration

```yaml
automation:
  - alias: "WLED Weather Effect"
    triggers:
      - trigger: state
        entity_id: sensor.weather
        to: "rainy"
    actions:
      - action: light.turn_on
        target:
          entity_id: light.wled
        data:
          effect: "Rain"
      - action: select.select_option
        target:
          entity_id: select.wled_color_palette
        data:
          option: "Breeze"
      - action: number.set_value
        target:
          entity_id: number.wled_intensity
        data:
          value: 200
      - action: number.set_value
        target:
          entity_id: number.wled_speed
        data:
          value: 255
```

## Segments

Each segment is a separate light entity:

```yaml
action: light.turn_on
target:
  entity_id: light.wled_segment_1
data:
  rgb_color: [255, 0, 0]
  brightness: 200
```

## Common Patterns

### Notification Flash

```yaml
automation:
  - alias: "Doorbell Flash"
    triggers:
      - trigger: state
        entity_id: binary_sensor.doorbell
        to: "on"
    actions:
      - action: light.turn_on
        target:
          entity_id: light.wled
        data:
          effect: "Strobe"
          rgb_color: [255, 255, 255]
      - delay: "00:00:05"
      - action: select.select_option
        target:
          entity_id: select.wled_preset
        data:
          option: "Default"
```

## Gotchas

1. **Turn on before preset** - Always `light.turn_on` before `select.select_option`
2. **Preset by name** - Use preset name string, not index number
3. **Service changes (2021.12+)** - Old `wled.effect` removed; use `select.select_option`
4. **Preset reset issue** - Modifying light after preset may reset preset selector

## Resources

- **Official Integration**: https://www.home-assistant.io/integrations/wled/
- **WLED Docs**: https://kno.wled.ge/advanced/home-automation/
