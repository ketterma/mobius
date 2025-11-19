# Inovelli VZM31-SN Blue Series 2-1 Switch Reference

Complete reference guide for Inovelli Blue Series switches in your Home Assistant setup.

## Overview

**Model:** VZM31-SN (Blue Series 2-1 Switch)
**Protocol:** Zigbee 3.0
**Integration:** ZHA (Zigbee Home Automation)
**Function:** Dimmer or On/Off switch (configurable)

### Certifications
- UL: E528330
- FCC: 2AQ7V-VZM31SN
- IC: 24756-VZM31SN
- Zigbee: ZIG22160ZB331395-24

### Physical Specs
- Depth: 1.2" (3.0cm)
- Height: 2.8" (7.1cm)
- Width: 1.6" (4.1cm)
- Range: Up to 100m line of sight

---

## Your Current Setup

### Switches in Use
Based on your automations, you have switches in these locations:

| Location | Switch Entity | Transition Entity | Target Light |
|----------|---------------|-------------------|--------------|
| Water Closet | `light.main_bathroom_water_closet_switch` | `number.main_bathroom_water_closet_switch_on_off_transition_time` | `light.hue_color_downlight_1_3` |
| Main Bathroom | `light.bathroom` | `number.bathroom_on_off_transition_time` | `light.main_bathroom_vanity` |
| Main Bathroom Perifo | `light.inovelli_vzm31_sn` | `number.inovelli_vzm31_sn_on_off_transition_time` | `light.main_bathroom_perifo` |
| Main Bedroom Primary | `light.bedroom` | `number.bedroom_on_off_transition_time` | `light.main_bedroom_lights` |
| Main Bedroom Secondary | `light.bedroom_secondary` | `number.bedroom_secondary_on_off_transition_time` | `light.main_bedroom_lights` |
| Main Closet | `light.closet_lights` | `number.closet_lights_on_off_transition_time` | `light.main_closet` |
| Bedroom Door | `light.bedroom_door` | `number.bedroom_door_on_off_transition_time` | `light.dymera_lights` |

All switches use the `jax/inovelli_hue.yaml` blueprint for Hue light control.

---

## Key Features

### 2-in-1 Functionality
- **Dimmer Mode:** Smooth dimming control
- **On/Off Mode:** Binary switching (configurable via parameter)

### Smart Bulb Mode
Allows constant power to smart bulbs while using the switch as a controller. The switch sends Zigbee commands instead of cutting power, preserving bulb connectivity.

### Multi-Way Support
- Works with dumb switches (neutral required)
- Works with Inovelli Aux switches
- Works with additional Inovelli switches via Zigbee binding

### LED Notification Bar
7-segment LED bar with per-LED customization:
- Colors: 0-255 (hue values)
- Intensity: 0-100% (101 = sync with default)
- Effects: Solid, blink, pulse, aurora, chase, etc.

---

## ZHA Event Commands

The switch generates `zha_event` events for button presses. Use these in automations.

### Button Mapping
- **Button 1:** Down paddle
- **Button 2:** Up paddle
- **Button 3:** Config/favorites button

### Command Types

| Command | Description |
|---------|-------------|
| `button_X_press` | Single tap |
| `button_X_double` | Double tap |
| `button_X_triple` | Triple tap |
| `button_X_quadruple` | Quad tap |
| `button_X_quintuple` | 5x tap |
| `button_X_hold` | Hold down |
| `button_X_release` | Release from hold |

### Example: Listen to Events

In Home Assistant UI: **Developer Tools → Events → Listen to events**

Enter `zha_event` and click "Start listening", then press a button to see:
```yaml
event_type: zha_event
data:
  device_id: "abc123..."
  unique_id: "00:11:22:33:44:55:66:77:1:0x0006"
  device_ieee: "00:11:22:33:44:55:66:77"
  endpoint_id: 1
  cluster_id: 6
  command: "button_2_double"
```

---

## Configuration Parameters

The VZM31-SN has 80+ configurable parameters accessible via ZHA. Parameters are stored in the custom Inovelli cluster `0xFC31` (64561 decimal).

### Common Parameters

#### Dimming Speed (0-127, in 100ms increments)
- **DimmingSpeedUpRemote:** Speed when controlled from hub
- **DimmingSpeedUpLocal:** Speed when controlled at switch
- **DimmingSpeedDownRemote:** Off-dimming from hub
- **DimmingSpeedDownLocal:** Off-dimming at switch

#### Ramp Rates (0-127)
- **RampRateOffToOnRemote/Local:** Turn-on transition
- **RampRateOnToOffRemote/Local:** Turn-off transition

#### Brightness Levels (0-255)
- **MinimumLevel:** Lowest dimming point
- **MaximumLevel:** Highest dimming point
- **DefaultLevelLocal/Remote:** Startup brightness (0 = previous)

#### Switch Behavior
- **InvertSwitch:** Reverse paddle orientation
- **OutputMode:** Dimmer or On/Off
- **SwitchType:** Single Pole / 3-Way Dumb / 3-Way Aux
- **LocalProtection:** Disable wall control
- **RemoteProtection:** Disable hub control

#### LED Settings
- **LEDColorWhenOn:** Bar color when switch is on (0-255)
- **LEDColorWhenOff:** Bar color when switch is off (0-255)
- **LEDIntensityWhenOn:** Brightness when on (0-100)
- **LEDIntensityWhenOff:** Brightness when off (0-100)

#### Automation
- **AutoTimerOff:** Auto-off after X seconds (0-32767)
- **ButtonDelay:** Multi-tap detection delay (0-900ms)
- **DoubleTapUpToParam55:** Level for double-tap up
- **DoubleTapDownToParam56:** Level for double-tap down

### Accessing Parameters in HA

Parameters appear as entities in Home Assistant:
- `number.{switch_name}_on_off_transition_time`
- `number.{switch_name}_dimming_speed_up_local`
- `switch.{switch_name}_smart_bulb_mode`
- etc.

You can also configure via:
1. **ZHA Toolkit (HACS):** Service calls to write attributes
2. **ZHA UI:** Device page → Manage Clusters → Cluster 64561

---

## LED Notifications

Send animated notifications to the LED bar using ZHA cluster commands.

### Service Call Structure

```yaml
service: zha.issue_zigbee_cluster_command
data:
  ieee: "00:11:22:33:44:55:66:77"  # Device IEEE address
  endpoint_id: 1
  cluster_id: 64561                # Inovelli cluster (0xFC31)
  cluster_type: in
  command: 1                       # 1 = all LEDs, 3 = specific LED
  command_type: server
  manufacturer: 4655               # Inovelli manufacturer code
  params:
    effect: "Pulse"
    color: 0                       # Red
    level: 100                     # Brightness %
    duration: 10                   # Seconds (255 = indefinite)
```

### Effect Types
- Off, Clear (stop notification)
- Solid
- Slow Blink, Medium Blink, Fast Blink
- Pulse
- Aurora
- Slow/Medium/Fast Falling
- Slow/Medium/Fast Rising
- Slow/Medium/Fast Chase
- Open/Close, Small/Big
- Siren

### Color Values (Hue Wheel)
| Color | Value |
|-------|-------|
| Red | 0 |
| Orange | 21 |
| Yellow | 42 |
| Green | 85 |
| Cyan | 127 |
| Blue | 170 |
| Purple | 212 |
| Pink | 234 |
| White | 255 |

Use the [Inovelli Notification Calculator](https://inovelliusa.github.io/inovelli-notification-calc/) for precise values.

### Blueprint for LED Notifications

Install the community blueprint for easier notifications:
- [ZHA Inovelli LED Notification Script](https://community.home-assistant.io/t/zha-inovelli-blue-series-2-1-switch-led-notification-script/579927)

Example uses:
- Flash red when door unlocked
- Pulse blue when washer done
- Solid green when alarm armed

---

## Automation Examples

### Multi-Tap Scene Control

```yaml
automation:
  - alias: "Movie Mode - Triple Tap Up"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: "your_device_id"
          command: "button_2_triple"
    action:
      - service: scene.turn_on
        target:
          entity_id: scene.movie_mode
```

### Config Button for Special Actions

```yaml
automation:
  - alias: "Toggle All Lights - Config Double Tap"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: "your_device_id"
          command: "button_3_double"
    action:
      - service: light.toggle
        target:
          entity_id: light.all_lights
```

### Notification on Motion Detected

```yaml
script:
  notify_motion_detected:
    sequence:
      - service: zha.issue_zigbee_cluster_command
        data:
          ieee: "{{ states.light.bedroom.attributes.ieee }}"
          endpoint_id: 1
          cluster_id: 64561
          cluster_type: in
          command: 1
          command_type: server
          manufacturer: 4655
          params:
            effect: "Fast Blink"
            color: 0
            level: 100
            duration: 5
```

---

## Your Blueprint: Inovelli → Hue

Your `jax/inovelli_hue.yaml` blueprint creates a "pretend-bind" that mirrors Inovelli switch actions to Hue lights without removing them from the Hue Bridge.

### Features
- Mirrors tap/hold/release semantics
- Respects switch's transition time settings
- Optional final sync to match Hue brightness to switch level
- Works off `zha_event` (no state polling)

### Inputs Required
1. **controller:** Device ID of the Inovelli switch
2. **target_light:** Hue light entity to control
3. **onoff_transition_number:** Switch's transition time entity
4. **switch_level_entity:** Switch's light entity for brightness sync

### Getting Device IDs

1. Go to **Developer Tools → Events**
2. Listen to `zha_event`
3. Press a button on the switch
4. Copy `device_id` from the event data

### Adding a New Switch

```yaml
- id: 'unique_id_here'
  alias: "New Room Switch"
  use_blueprint:
    path: jax/inovelli_hue.yaml
    input:
      controller: "device_id_from_zha_event"
      target_light: light.new_room_hue_lights
      onoff_transition_number: number.new_room_switch_on_off_transition_time
      switch_level_entity: light.new_room_switch
```

---

## Firmware Updates

### Current Version
Check in ZHA: **Settings → Devices → [Switch] → Device Info → Firmware**

### Updating Firmware
1. Download latest from [Inovelli Firmware Releases](https://community.inovelli.com/t/blue-series-2-1-firmware-changelog-vzm31-sn/12326)
2. In HA: **Settings → Devices → [Switch] → Update Firmware**
3. Select the `.ota` file
4. Wait 10-15 minutes (switch may be unresponsive)

### After Update
- Reconfigure the device in ZHA to reload quirks
- Re-check parameter settings

---

## Direct Zigbee Binding (Hue Bulbs Without Bridge)

You can pair Hue bulbs directly to your ZHA coordinator and bind them to Inovelli switches, bypassing the Hue Bridge entirely. This section covers what you gain, what you lose, and how to set it up.

### What You Gain

| Benefit | Description |
|---------|-------------|
| **Speed** | Direct Zigbee binding is near-instantaneous (no hub roundtrip) |
| **Reliability** | Works even when Home Assistant is down |
| **Simplicity** | Fewer moving parts, one Zigbee network |
| **Local Control** | Switch controls bulb directly via Zigbee |

### What You Lose (Hue Bridge Features)

| Lost Feature | Impact |
|--------------|--------|
| **Hue Entertainment** | No music/movie/game sync (proprietary API) |
| **Dynamic Scenes** | No color-cycling scenes from Hue app |
| **Color Loop/Prism** | These effects are Hue Bridge exclusive |
| **Firmware Updates** | Bulbs won't receive updates without bridge |
| **Hue App** | Cannot use Hue app for control or configuration |
| **HomeKit via Hue** | Lose Apple HomeKit integration through bridge |
| **Optimized Scenes** | Hue scenes send simultaneous commands; HA sends one-by-one |

### Control Capabilities via ZHA

When Hue bulbs are paired directly to ZHA, you get:

**Full Control:**
- On/Off
- Brightness (0-255)
- Color temperature (Kelvin/mireds)
- RGB/HS/XY color
- Transitions

**Through Zigbee Binding:**
- On/Off (via OnOff cluster)
- Dimming (via LevelControl cluster)

**NOT Available via Binding:**
- Color control (no "Move to Color with OnOff" command)
- Color temperature changes
- Scene activation

### Setting Up Direct Binding (ZHA)

#### Prerequisites
1. Hue bulbs paired directly to ZHA (NOT through Hue Bridge)
2. Bulbs and switch on same Zigbee network
3. Switch in Smart Bulb Mode (if wired to bulb)

#### Step 1: Enable Smart Bulb Mode

If the bulb is wired to the switch (switch controls power):

1. Go to **Settings → Devices & Services → ZHA**
2. Click your switch → **Manage Clusters**
3. Select cluster: `Inovelli_VZM31SN_Cluster (Endpoint id: 1, Id: 0xfc31)`
4. Under Cluster Attributes, select `Smart Bulb Mode`
5. Set value to `1` and click **Set Zigbee Attribute**

This keeps constant power to the bulb while the switch sends Zigbee commands.

#### Step 2: Individual Binding (Single Bulb)

1. In the switch's **Manage Clusters** page
2. Scroll to **Binding** section
3. Select your Hue bulb (usually **Endpoint 11** for Hue)
4. Click **Bind**

#### Step 3: Group Binding (Multiple Bulbs)

1. Go to **Settings → Devices & Services → ZHA → Configure**
2. Click **Groups** tab → **Create Group**
3. Name the group and add your Hue bulbs
4. Click **Create Group**
5. Return to your switch → **Manage Clusters**
6. Scroll to **Group Binding**
7. Select your group
8. Check **LevelControl** and **OnOff** clusters
9. Select **Endpoint #1**
10. Click **Bind Group**

#### Step 4: Test

- Press up paddle → Bulb(s) should turn on
- Press down paddle → Bulb(s) should turn off
- Hold up/down → Bulb(s) should dim

### Clusters Explained

| Cluster | ID | Function |
|---------|-----|----------|
| **OnOff** | 0x0006 | On/off control |
| **LevelControl** | 0x0008 | Brightness/dimming |
| **ColorControl** | 0x0300 | Color and color temp (NOT bindable from switch) |

**Important:** The Inovelli switch can only bind OnOff and LevelControl. Color changes must come from Home Assistant automations.

### Multi-Tap and Scenes with Bindings

**What Works:**
- Single tap up/down (via binding, no hub needed)
- Hold to dim (via binding, no hub needed)
- Multi-tap scenes (requires hub, uses `zha_event`)
- Config button (requires hub)

**Trade-off:**
- Basic on/off/dim works without hub
- Scenes and multi-tap require hub to be online

**Button Delay Setting:**
If multi-tap events aren't reaching Home Assistant, increase the ButtonDelay parameter (default 500ms). Values below 300ms often cause issues.

### Hybrid Approach (Recommended)

You can use bindings for basic control AND Home Assistant for advanced features:

```yaml
automation:
  - alias: "Bedroom Triple-Tap - Night Mode"
    trigger:
      - platform: event
        event_type: zha_event
        event_data:
          device_id: "your_switch_id"
          command: "button_2_triple"
    action:
      # Color control must come from HA, not binding
      - service: light.turn_on
        target:
          entity_id: light.hue_bedroom_bulb
        data:
          brightness_pct: 10
          color_temp_kelvin: 2000
          transition: 2
```

### Known Issues

#### Dimming "Bounce"
The switch and bulb may have different dimming speeds, causing a slight bounce at the end of dimming. Adjust the switch's dimming speed parameters to match bulb behavior.

#### Color Flash on Turn-On
Unlike LevelControl (which has "Move to Level with OnOff"), there's no atomic "Move to Color with OnOff" command. If you turn on a bulb and set color simultaneously via HA, the bulb may briefly flash its previous color.

**Workaround:** Set color first with a tiny transition, then turn on:
```yaml
sequence:
  - service: light.turn_on
    target:
      entity_id: light.bedroom
    data:
      rgb_color: [255, 100, 50]
      brightness: 1
      transition: 0
  - delay:
      milliseconds: 50
  - service: light.turn_on
    target:
      entity_id: light.bedroom
    data:
      brightness: 200
      transition: 1
```

#### Power-On Behavior
Hue bulbs default to full brightness warm white when power is restored. Without the Hue Bridge, changing this default is difficult (requires direct Zigbee attribute writes that may not persist).

### Comparison: Your Current Setup vs Direct Binding

| Feature | Current (Hue Bridge + Blueprint) | Direct Binding |
|---------|----------------------------------|----------------|
| Speed | ~100-200ms (via HA) | ~50ms (direct) |
| Works offline | No | Basic on/off/dim only |
| Color control | Full (via HA) | Via HA only (not binding) |
| Multi-tap scenes | Yes | Yes (requires HA) |
| Hue scenes | Yes (smooth) | No |
| Entertainment | Yes | No |
| Firmware updates | Yes | No |
| Setup complexity | Medium | Low |

### Recommendation

**Keep using the Hue Bridge** if you want:
- Smooth Hue scenes with simultaneous commands
- Hue Entertainment features
- Easy firmware updates
- Color control via switch (through your blueprint)

**Consider direct binding** if you want:
- Fastest possible response time
- Basic control when HA is down
- Simpler single-network setup
- Don't need Hue-specific features

**Best of both worlds:** Use Hue Bridge for most bulbs but directly bind a few critical switches (like bathroom) for reliability.

---

## Troubleshooting

### Switch Not Responding to Multi-Tap
- Check **ButtonDelay** parameter (higher = more reliable multi-tap detection)
- Ensure automation mode is `queued` or `restart` for rapid events

### Parameters Not Appearing
- Ensure you're on latest firmware
- Remove and re-pair the device
- Check ZHA quirk is loaded (may need HA restart)

### LED Notifications Not Working
- Verify `cluster_id: 64561` (not 6 or 8)
- Check IEEE address is correct
- Ensure `manufacturer: 4655` is set

### Dimming Issues
- Adjust **MinimumLevel** if lights flicker at low brightness
- Set **QuickStartTime/Level** for LED bulbs that need initial power boost
- Check **HigherOutputInNonNeutral** if using without neutral wire

### Binding Issues
- Clear existing bindings before creating new ones
- Use **Smart Bulb Mode** when controlling smart bulbs via binding

---

## Useful Resources

### Official
- [Inovelli Help Center](https://help.inovelli.com/)
- [Blue Series ZHA Setup Guide](https://help.inovelli.com/en/articles/8452425-blue-series-dimmer-switch-setup-instructions-home-assistant-zha)
- [Multi-Tap Scene Control Guide](https://help.inovelli.com/en/articles/8477986-setting-up-multi-tap-scene-control-home-assistant-zha)
- [Firmware Changelog](https://community.inovelli.com/t/blue-series-2-1-firmware-changelog-vzm31-sn/12326)

### Community
- [Zigbee2MQTT Device Page](https://www.zigbee2mqtt.io/devices/VZM31-SN.html)
- [ZHA LED Notification Blueprint](https://community.home-assistant.io/t/zha-inovelli-blue-series-2-1-switch-led-notification-script/579927)
- [ZHA VZM31-SN Blueprint](https://community.home-assistant.io/t/zha-inovelli-vzm31-sn-blue-series-2-1-switch/479148)
- [Notification Calculator](https://inovelliusa.github.io/inovelli-notification-calc/)

### GitHub
- [ZHA Device Handlers (quirks)](https://github.com/zigpy/zha-device-handlers)
- [Inovelli Firmware](https://github.com/InovelliUSA/Firmware)

---

## Automation Ideas for Your Setup

### Based on Your Current Switches

1. **Bathroom Night Mode**
   - Double-tap down on Water Closet switch → Dim bathroom to 10%
   - Triple-tap down → Turn off all bathroom lights

2. **Bedroom Scene Control**
   - Triple-tap up on Primary → Turn on all bedroom lights to 100%
   - Triple-tap down on Primary → Nightstand only at 20%
   - Config button hold → Toggle ceiling fan

3. **Closet Auto-Off**
   - Set AutoTimerOff to 300 seconds (5 min) on closet switch

4. **Door Status Notifications**
   - Pulse blue on bedroom switches when garage door opens
   - Solid red on all switches when front door unlocked

5. **Motion-Triggered Fades**
   - On bathroom motion: fade in Water Closet → Main Bathroom sequence
   - Clear notification after 30 seconds of no motion

### Config Button Ideas
The config/favorites button (button_3) is unused in your current setup and perfect for:
- Single tap: Toggle "away" mode
- Double tap: All lights off
- Triple tap: Activate specific scene
- Hold: Toggle smart bulb mode (for bulb changes)
