# Philips Hue Advanced Automation Reference

Complete guide to advanced Hue automation patterns in Home Assistant.

## Overview

**Integration:** Philips Hue (via Hue Bridge)
**API Version:** V2 (event streaming, instant updates)
**Key Advantage:** Native Hue scenes send commands to all lights simultaneously for smooth transitions

---

## Your Current Hue Setup

### Light Groups (configuration.yaml)

| Group Entity | Lights | Purpose |
|--------------|--------|---------|
| `light.main_bathroom_vanity` | 5 downlights | Controlled by Main Bathroom Switch |
| `light.main_bathroom_perifo` | 3 Perifo spots | Controlled by Perifo Switch |
| `light.main_closet` | 2 downlights | Controlled by Closet Switch |
| `light.main_bedroom_lights` | 4 downlights | Controlled by Primary/Secondary Bedroom Switches |
| `light.dymera_lights` | 4 Dymera lights | Controlled by Bedroom Door Switch |

**Individual Lights:**
- `light.hue_color_downlight_1_3` (Water Closet)
- Various other Hue Color Downlights

---

## Hue Integration Services

### hue.activate_scene

Advanced service for activating Hue scenes with customizable properties.

```yaml
service: hue.activate_scene
target:
  entity_id: scene.living_room_relax
data:
  transition: 2           # Fade duration in seconds
  dynamic: true           # Enable dynamic color cycling
  speed: 50               # Dynamic mode speed (1-100)
  brightness: 80          # Override brightness (1-100)
```

**Parameters:**
- `entity_id` (required): Scene entity to activate
- `transition`: Duration in seconds for color/brightness transition
- `dynamic`: Enable/disable Hue dynamic scenes (color cycling)
- `speed`: Dynamic palette cycling speed
- `brightness`: Override scene brightness percentage

### Why Use Hue Scenes Over HA Scenes

**Hue Scenes (Recommended):**
- Commands sent to all lights simultaneously
- Smooth, coordinated transitions
- Optimized by Hue Bridge

**HA Scenes:**
- Commands sent to lights one-by-one
- Perceptible lag between lights
- Less smooth user experience

**Best Practice:** Create scenes in the Hue app, then use `hue.activate_scene` in automations.

---

## Light Services for Hue Bulbs

### light.turn_on

```yaml
service: light.turn_on
target:
  entity_id: light.bedroom_lamp
data:
  brightness: 200           # 0-255
  # OR
  brightness_pct: 80        # 0-100%

  # Color options (use only one)
  rgb_color: [255, 100, 50]       # RGB values [0-255]
  hs_color: [30, 80]              # Hue 0-360, Saturation 0-100
  xy_color: [0.5, 0.4]            # CIE xy color space
  color_temp_kelvin: 3000         # Color temperature in Kelvin
  color_name: "coral"             # CSS3 color name

  # Transition and effects
  transition: 2                   # Fade duration in seconds
  flash: "short"                  # "short" or "long"
  effect: "colorloop"             # Special effects

  # Built-in profiles
  profile: "relax"                # relax, energize, concentrate, reading
```

### light.turn_off

```yaml
service: light.turn_off
target:
  entity_id: light.bedroom_lamp
data:
  transition: 5              # Fade out duration
  flash: "short"             # Flash before turning off
```

### light.toggle

Same parameters as `light.turn_on`, toggles current state.

### Brightness Adjustment

```yaml
service: light.turn_on
target:
  entity_id: light.bedroom_lamp
data:
  brightness_step: 25        # Increase by 25 (0-255)
  # OR
  brightness_step_pct: 10    # Increase by 10%
  # Use negative values to decrease
```

---

## Color Modes and Temperature

### Color Temperature Range
- **Warm:** 2000K (candlelight)
- **Neutral:** 4000K (daylight)
- **Cool:** 6500K (blue-white)

```yaml
service: light.turn_on
target:
  entity_id: light.desk_lamp
data:
  color_temp_kelvin: 3000    # Warm white
  # OR in mireds (1,000,000 / Kelvin)
  color_temp: 333            # Same as 3000K
```

### Built-in Profiles

```yaml
service: light.turn_on
target:
  entity_id: light.office
data:
  profile: "concentrate"     # Options: relax, energize, concentrate, reading
```

---

## Hue Events (hue_event)

Physical Hue remotes and buttons emit `hue_event` when pressed.

### Listening for Events

1. Go to **Developer Tools → Events**
2. Enter `hue_event` and click "Start listening"
3. Press a button on your Hue remote

### Event Structure

```yaml
event_type: hue_event
data:
  device_id: "abc123..."
  unique_id: "00:17:88:01:xx:xx:xx:xx"
  type: "initial_press"      # or "repeat", "short_release", "long_release"
  subtype: 1                 # Button number
```

### Rate Limiting

**Important:** Hue API limits button events to 1 per second per device.

### Hue Dimmer Switch Events

| Button | Number | Events |
|--------|--------|--------|
| On | 1 | `1_click`, `1_hold` |
| Brightness Up | 2 | `2_click`, `2_hold` |
| Brightness Down | 3 | `3_click`, `3_hold` |
| Off | 4 | `4_click`, `4_hold` |

### Automation Example

```yaml
automation:
  - alias: "Hue Dimmer - On Button Double Press"
    trigger:
      - platform: device
        device_id: "your_dimmer_device_id"
        domain: hue
        type: "short_release"
        subtype: 1
        id: "on_press"
    action:
      - service: scene.turn_on
        target:
          entity_id: scene.bright_mode
```

---

## Hue Motion Sensors

### Available Entities

When connected, each Hue motion sensor exposes:
- **Binary sensor:** `binary_sensor.hallway_motion` (occupancy)
- **Sensor:** `sensor.hallway_temperature`
- **Sensor:** `sensor.hallway_illuminance` (lux)
- **Switch:** `switch.hallway_motion_sensor_enabled` (V2 API)

### Motion + Illuminance Automation

```yaml
automation:
  - alias: "Motion Light - Dark Only"
    trigger:
      - platform: state
        entity_id: binary_sensor.bathroom_motion
        to: "on"
    condition:
      - condition: numeric_state
        entity_id: sensor.bathroom_illuminance
        below: 100                    # Only if dark (lux < 100)
    action:
      - service: light.turn_on
        target:
          entity_id: light.main_bathroom_vanity
        data:
          brightness_pct: 50
          transition: 1
```

### Auto-Off When No Motion

```yaml
automation:
  - alias: "Bathroom Light Off - No Motion"
    trigger:
      - platform: state
        entity_id: binary_sensor.bathroom_motion
        to: "off"
        for:
          minutes: 5
    action:
      - service: light.turn_off
        target:
          entity_id: light.main_bathroom_vanity
        data:
          transition: 3
```

### Known Issues

**Lux Reading Stale After Light Off:**
When a light turns off, the sensor may still report high lux values momentarily. If motion is detected immediately, the automation may not trigger.

**Solutions:**
1. Add a delay before checking lux
2. Use a helper to track "light recently on" state
3. Use lower lux threshold

---

## Adaptive Lighting

Automatically adjust brightness and color temperature based on time of day.

### Installation (HACS)

1. Add repository: `basnijholt/adaptive-lighting`
2. Install and restart Home Assistant
3. Configure via **Settings → Devices & Services → Adaptive Lighting**

### Key Features

- **Circadian Rhythm:** Cooler colors midday, warmer at night
- **Sleep Mode:** Minimal brightness, very warm colors
- **Manual Control Detection:** Pauses adjustments when you override
- **Four Control Switches:** Per-room control over the feature

### Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| `min_brightness` | Minimum brightness % | 1 |
| `max_brightness` | Maximum brightness % | 100 |
| `min_color_temp` | Warmest temperature (K) | 2000 |
| `max_color_temp` | Coolest temperature (K) | 5500 |
| `sleep_brightness` | Brightness in sleep mode | 1 |
| `sleep_color_temp` | Color temp in sleep mode | 1000 |
| `transition` | Transition duration (s) | 45 |
| `take_over_control` | Detect manual changes | true |

### Services

**Apply current settings immediately:**
```yaml
service: adaptive_lighting.apply
data:
  entity_id: switch.adaptive_lighting_bedroom
  lights: light.main_bedroom_lights
  transition: 1
```

**Mark light as manually controlled:**
```yaml
service: adaptive_lighting.set_manual_control
data:
  entity_id: switch.adaptive_lighting_bedroom
  lights: light.main_bedroom_lights
  manual_control: true
```

**Change settings dynamically:**
```yaml
service: adaptive_lighting.change_switch_settings
data:
  entity_id: switch.adaptive_lighting_bedroom
  min_brightness: 20
  sleep_brightness: 5
```

### Sleep Mode Automation

```yaml
automation:
  - alias: "Enable Adaptive Lighting Sleep Mode"
    trigger:
      - platform: time
        at: "22:00:00"
    action:
      - service: switch.turn_on
        target:
          entity_id: switch.adaptive_lighting_sleep_mode_bedroom
```

---

## Home Assistant Light Groups

### Group Platform (Your Setup)

Defined in `configuration.yaml`:

```yaml
light:
  - platform: group
    name: Main Bathroom Vanity
    entities:
      - light.hue_color_downlight_5_3
      - light.hue_color_downlight_8
      # etc.
```

**Pros:**
- Simple configuration
- Group behaves like single light
- Supports all light services

**Cons:**
- Commands sent one-by-one (less smooth)
- No scene support

### Hue Room/Zone Groups (Alternative)

Enable in **Settings → Integrations → Hue → Entities**

**Pros:**
- Commands sent simultaneously (smoother)
- Native Hue scene support
- Better performance

**Cons:**
- Must maintain in Hue app
- Less flexible naming

### When to Use Each

| Approach | Best For |
|----------|----------|
| HA Light Groups | Mixing Hue + non-Hue lights |
| Hue Room Groups | All-Hue rooms needing smooth transitions |
| Hue Scenes | Coordinated multi-light states |

---

## Advanced Automation Patterns

### Time-Based Scene Activation

```yaml
automation:
  - alias: "Bathroom Light - Time-Aware"
    trigger:
      - platform: state
        entity_id: binary_sensor.bathroom_motion
        to: "on"
    action:
      - choose:
          # Morning (6am - 9am)
          - conditions:
              - condition: time
                after: "06:00:00"
                before: "09:00:00"
            sequence:
              - service: hue.activate_scene
                target:
                  entity_id: scene.bathroom_energize
                data:
                  brightness: 100
          # Evening (6pm - 10pm)
          - conditions:
              - condition: time
                after: "18:00:00"
                before: "22:00:00"
            sequence:
              - service: hue.activate_scene
                target:
                  entity_id: scene.bathroom_relax
                data:
                  brightness: 70
          # Night (10pm - 6am)
          - conditions:
              - condition: time
                after: "22:00:00"
                before: "06:00:00"
            sequence:
              - service: light.turn_on
                target:
                  entity_id: light.main_bathroom_vanity
                data:
                  brightness_pct: 10
                  color_temp_kelvin: 2200
        default:
          - service: hue.activate_scene
            target:
              entity_id: scene.bathroom_bright
```

### Dynamic Scene Toggle

```yaml
automation:
  - alias: "Toggle Dynamic Scene Mode"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: "bedroom_switch_id"
          command: "button_3_triple"   # Config button triple tap
    action:
      - service: hue.activate_scene
        target:
          entity_id: scene.bedroom_aurora
        data:
          dynamic: "{{ not is_state_attr('scene.bedroom_aurora', 'dynamics', true) }}"
```

### Gradual Wake-Up Light

```yaml
automation:
  - alias: "Sunrise Wake-Up"
    trigger:
      - platform: time
        at: "06:30:00"
    action:
      # Start dim and warm
      - service: light.turn_on
        target:
          entity_id: light.main_bedroom_lights
        data:
          brightness: 1
          color_temp_kelvin: 2000
          transition: 0
      # Gradually increase over 30 minutes
      - repeat:
          count: 30
          sequence:
            - delay:
                minutes: 1
            - service: light.turn_on
              target:
                entity_id: light.main_bedroom_lights
              data:
                brightness_step: 8
                color_temp_kelvin: "{{ 2000 + (repeat.index * 100) | int }}"
                transition: 60
```

### Flash Notification

```yaml
script:
  notify_flash:
    sequence:
      - repeat:
          count: 3
          sequence:
            - service: light.turn_on
              target:
                entity_id: light.main_bathroom_vanity
              data:
                brightness: 255
                rgb_color: [255, 0, 0]
                transition: 0.2
            - delay:
                milliseconds: 300
            - service: light.turn_off
              target:
                entity_id: light.main_bathroom_vanity
              data:
                transition: 0.2
            - delay:
                milliseconds: 300
```

### Occupancy-Based Room Control

```yaml
automation:
  - alias: "Bedroom Occupied - Activate Scene"
    trigger:
      - platform: state
        entity_id: binary_sensor.bedroom_occupancy
        to: "on"
    action:
      - choose:
          - conditions:
              - condition: sun
                after: sunset
            sequence:
              - service: hue.activate_scene
                target:
                  entity_id: scene.bedroom_evening
          - conditions:
              - condition: sun
                before: sunrise
            sequence:
              # Don't turn on lights at night
              - stop: "Night time - skip"
        default:
          - service: hue.activate_scene
            target:
              entity_id: scene.bedroom_bright
```

---

## Integration with Inovelli Switches

Your current setup uses Inovelli switches to control Hue lights via the `jax/inovelli_hue.yaml` blueprint.

### Coordinated Transitions

The blueprint reads the switch's transition time setting and applies it to Hue commands:

```yaml
# Blueprint reads this entity
number.bedroom_on_off_transition_time

# And uses it in light.turn_on
transition: "{{ onoff_sec }}"
```

### Adding Multi-Tap Scenes

Extend your Inovelli switches with scene control:

```yaml
automation:
  - alias: "Bedroom Triple-Tap Up - Movie Mode"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: "a4725fafbb5c890f438fdbb217e5a065"  # Primary bedroom switch
          command: "button_2_triple"
    action:
      - service: hue.activate_scene
        target:
          entity_id: scene.bedroom_movie
        data:
          transition: 2
          brightness: 30

  - alias: "Bedroom Triple-Tap Down - Sleep Mode"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: "a4725fafbb5c890f438fdbb217e5a065"
          command: "button_1_triple"
    action:
      - service: light.turn_on
        target:
          entity_id: light.main_bedroom_lights
        data:
          brightness_pct: 5
          color_temp_kelvin: 2000
          transition: 3
```

---

## Scene Presets (Custom Component)

For Hue-like scene behavior with any light (not just Hue):

### Installation (HACS)

Repository: `Hypfer/hass-scene_presets`

### Features

- **Dynamic Scenes:** Colors cycle continuously with configurable transitions
- **Smart Shuffle:** Smooth color transitions when randomizing
- **Custom Brightness:** Override preset brightness
- **Works with any light entity**

### Service Calls

```yaml
# Activate a preset
service: scene_presets.apply
data:
  entity_id: light.bedroom_group
  preset: "warm"
  brightness: 80

# Enable dynamic mode
service: scene_presets.apply
data:
  entity_id: light.bedroom_group
  preset: "aurora"
  dynamic: true
  interval: 60              # Change every 60 seconds
  transition: 30            # 30 second fade between colors
```

---

## Troubleshooting

### Lights Flash When Turning On

**Cause:** Bulb turns on at previous state, then HA sends new command.

**Solutions:**
1. Use Hue scenes instead of individual light commands
2. Set `transition: 0` for immediate state change
3. Use `hue.activate_scene` with brightness override

### Transitions Not Working

**Check:**
1. Bulb supports transitions (most Hue do)
2. Transition value is in seconds (not milliseconds)
3. Other automations aren't overriding

### Scene Colors Look Wrong

**Cause:** Different bulbs have different color capabilities.

**Solutions:**
1. Use Hue scenes (optimized per-bulb)
2. Set explicit color values for each bulb
3. Use `xy_color` for most accurate colors

### Motion Sensor Slow Response

**V1 Bridge:** Polled every 5 seconds (inherent delay)
**V2 Bridge:** Event streaming (instant)

**If V2 still slow:**
1. Check for automations with `for:` delays
2. Ensure HA is processing events (check logs)
3. Consider Zigbee2MQTT for direct sensor control

### Hue Bridge Disconnects

1. Assign static IP to bridge
2. Check network stability
3. Ensure only one integration instance

---

## Useful Resources

### Official Documentation
- [Philips Hue Integration](https://www.home-assistant.io/integrations/hue/)
- [Light Integration](https://www.home-assistant.io/integrations/light/)

### Custom Components
- [Adaptive Lighting](https://github.com/basnijholt/adaptive-lighting)
- [Scene Presets](https://github.com/Hypfer/hass-scene_presets)

### Community
- [Hue Community Forum](https://community.home-assistant.io/c/configuration/hue/)
- [Circadian Lighting Blueprints](https://community.home-assistant.io/t/automatic-circadian-lighting-match-your-lights-color-temperature-to-the-sun/472105)

---

## Automation Ideas for Your Setup

### Based on Your Current Configuration

1. **Morning Routine**
   - Time trigger + motion → Activate "Energize" scene in bathroom
   - Gradual brightness increase in bedroom

2. **Night Mode**
   - After 10pm → All lights at 10% brightness, 2200K
   - Motion sensors reduce sensitivity

3. **Away Mode**
   - Random light activation when away
   - Simulate occupancy patterns

4. **Bathroom Sequence**
   - Motion detected → Water closet first
   - 3 seconds later → Vanity lights
   - No motion 10 minutes → Fade off

5. **Closet Auto-Control**
   - Door sensor open → Lights on at 100%
   - Door sensor closed → Lights off after 30s

6. **Bedroom Wind-Down**
   - 9pm → Start reducing color temperature
   - 10pm → Sleep mode (very dim, very warm)
   - Motion disabled during sleep hours

7. **Scene Shortcuts via Inovelli**
   - Double-tap up → "Bright" mode
   - Double-tap down → "Relax" mode
   - Triple-tap config → Toggle all room lights
