# Philips Hue

## Integration Options

| Method | Pros | Cons |
|--------|------|------|
| Native (Hue Bridge) | Push updates, scenes, entertainment | Requires bridge |
| Zigbee2MQTT | Direct control, no bridge | No Hue app features |

## Scenes

Scenes are imported automatically as `scene.hue_*` entities. Create/edit them in the official Hue app.

```yaml
# Basic scene activation
action: scene.turn_on
target:
  entity_id: scene.hue_living_room_relax

# With transition and brightness
action: hue.activate_scene
data:
  entity_id: scene.hue_bedroom_nightlight
  transition: 2
  brightness: 180

# Dynamic scene (animated)
action: hue.activate_scene
data:
  entity_id: scene.hue_living_room_energize
  dynamic: true
  speed: 50  # 0-100
```

## Groups (Rooms/Zones)

Groups are auto-created but **disabled by default**. Enable at:
Settings > Integrations > Hue > entities

```yaml
# Control entire room
action: light.turn_on
target:
  entity_id: light.living_room  # Hue room group
data:
  brightness_pct: 80
  color_temp_kelvin: 3000
```

**Tip**: Use Hue scenes for multi-light control - smoother than individual commands.

## Common Patterns

### Presence-Based Lighting

```yaml
automation:
  - alias: "Welcome Home"
    triggers:
      - trigger: state
        entity_id: person.john
        to: "home"
    conditions:
      - condition: sun
        after: sunset
    actions:
      - action: hue.activate_scene
        data:
          entity_id: scene.hue_hallway_welcome
          transition: 3
```

### Time-Based Scenes

```yaml
automation:
  - alias: "Evening Lighting"
    triggers:
      - trigger: sun
        event: sunset
        offset: "00:30:00"
    actions:
      - action: hue.activate_scene
        data:
          entity_id: scene.hue_living_room_relax
          dynamic: true
```

## Gotchas

1. **Groups disabled by default** - Must manually enable room/zone entities
2. **Scenes created in Hue app only** - Cannot create in Home Assistant
3. **V1 bridge limitations** - No auto-created scenes, uses polling
4. **Button rate limiting** - 1 event per second per device

## Resources

- **Official Integration**: https://www.home-assistant.io/integrations/hue/
- **Emulated Hue**: https://github.com/hass-emulated-hue/core
