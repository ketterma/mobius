# Inovelli Switches

## LED Notification Parameters

The LED bar is programmed by encoding color, brightness, duration, and effect into a single integer.

**Calculator**: https://nathanfiscus.github.io/inovelli-notification-calc/

| Parameter | Values |
|-----------|--------|
| Color | 0-255 hue (0=Red, 85=Green, 170=Blue, 255=White) |
| Brightness | 1-10 |
| Duration | 1-254 seconds, 255=indefinite |
| Effect | Off, Solid, Slow Blink, Fast Blink, Pulse, Chase |

## Z-Wave JS Examples

```yaml
# Set notification (dimmer uses param 16, switch uses param 8)
action: zwave_js.bulk_set_partial_config_parameters
data:
  parameter: "16"
  value: 83823268  # Dark Blue, 10 brightness, infinite, Slow Blink
target:
  device_id: YOUR_DEVICE_ID

# Clear notification
action: zwave_js.bulk_set_partial_config_parameters
data:
  parameter: "16"
  value: 16714408  # Effect: Off
target:
  device_id: YOUR_DEVICE_ID
```

## Button Events

Z-Wave JS fires `zwave_js_value_notification` events:

| Property Key | Button |
|--------------|--------|
| `"001"` | Down |
| `"002"` | Config |
| `"003"` | Up |

| Value | Action |
|-------|--------|
| `KeyPressed` | Single press |
| `KeyPressed2x` | Double press |
| `KeyPressed3x` | Triple press |
| `KeyHeldDown` | Hold start |
| `KeyReleased` | Hold end |

```yaml
automation:
  - alias: "Inovelli Double Tap Up"
    triggers:
      - trigger: event
        event_type: zwave_js_value_notification
        event_data:
          device_id: YOUR_DEVICE_ID
          property_key: "003"
          value: "KeyPressed2x"
    actions:
      - action: scene.turn_on
        target:
          entity_id: scene.movie_mode
```

## Blue Series (Zigbee2MQTT)

```yaml
action: mqtt.publish
data:
  topic: "zigbee2mqtt/inovelli_dimmer/set"
  payload: '{"led_effect":{"color":1,"duration":30,"effect":"fast_blink","level":100}}'
```

## Common Patterns

### Status Indicator

```yaml
automation:
  - alias: "Door Unlocked Warning"
    triggers:
      - trigger: state
        entity_id: lock.front_door
        to: "unlocked"
        for:
          minutes: 5
    actions:
      - action: zwave_js.bulk_set_partial_config_parameters
        data:
          parameter: "16"
          value: 16711935  # Red, pulse, infinite
        target:
          device_id: SWITCH_DEVICE_ID

  - alias: "Clear Door Warning"
    triggers:
      - trigger: state
        entity_id: lock.front_door
        to: "locked"
    actions:
      - action: zwave_js.bulk_set_partial_config_parameters
        data:
          parameter: "16"
          value: 16714408
        target:
          device_id: SWITCH_DEVICE_ID
```

## Gotchas

1. **Entity name limits** - Rename Z-Wave entities to shorter names if you get errors
2. **All four parameters required** - Must set duration, effect, brightness, AND color together
3. **Device vs Entity ID** - Button events use `device_id`, not the light/switch entity
4. **Switch firmware bug** - Some switches revert to blue after toggling (beta firmware fixes)

## Resources

- **Community Script**: https://community.home-assistant.io/t/inovelli-z-wave-red-series-notification-led/165483
- **Mega Tutorial**: https://michael-kehoe.io/post/inovelli-home-assistant-zwjavejs-mega-tutorial/
