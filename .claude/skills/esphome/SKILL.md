---
name: esphome
description: "ESPHome configuration, YAML, packages, substitutions, RATGDO garage door, ESP32-P4, Waveshare 86-panel, LVGL displays, OTA updates, sensors, GPIO. Use for creating or debugging ESPHome device configurations."
---

# ESPHome

## Quick Start

```yaml
esphome:
  name: my-device
  friendly_name: "My Device"

esp32:
  board: esp32dev
  framework:
    type: arduino

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  ap:
    ssid: "${name} Fallback"

captive_portal:

api:
  encryption:
    key: !secret api_key

ota:
  - platform: esphome
    password: !secret ota_password

logger:
  level: INFO
```

## Substitutions

Reusable values throughout your config:

```yaml
substitutions:
  device_name: office-sensor
  friendly_name: "Office Sensor"
  update_interval: 60s

esphome:
  name: ${device_name}
  friendly_name: ${friendly_name}

sensor:
  - platform: dht
    update_interval: ${update_interval}
```

## Packages

Modular, reusable configurations:

```yaml
packages:
  # Local packages
  wifi: !include common/wifi.yaml
  base: !include common/esp32-base.yaml

  # Remote packages
  ratgdo:
    url: https://github.com/ratgdo/esphome-ratgdo
    ref: main
    files: [base.yaml]
    refresh: 1d
```

**Merge behavior**: Dictionaries merge by key, lists concatenate or merge by ID.

## Common Sensor Patterns

### I2C Sensors (BME280, etc.)

```yaml
i2c:
  sda: GPIO21
  scl: GPIO22
  scan: true

sensor:
  - platform: bme280_i2c
    temperature:
      name: "${friendly_name} Temperature"
      oversampling: 16x
    pressure:
      name: "${friendly_name} Pressure"
    humidity:
      name: "${friendly_name} Humidity"
    update_interval: 60s
```

### Binary Sensors

```yaml
binary_sensor:
  - platform: gpio
    pin:
      number: GPIO4
      mode: INPUT_PULLUP
      inverted: true
    name: "${friendly_name} Motion"
    device_class: motion
    on_press:
      - homeassistant.event:
          event: esphome.motion_detected
          data:
            location: "${friendly_name}"
```

### Template Sensors

```yaml
sensor:
  - platform: template
    name: "Calculated Value"
    lambda: |-
      return id(sensor_a).state + id(sensor_b).state;
    update_interval: 60s
```

## Switches and Outputs

```yaml
switch:
  - platform: gpio
    pin: GPIO5
    name: "${friendly_name} Relay"
    id: relay
    restore_mode: ALWAYS_OFF
    on_turn_on:
      - logger.log: "Relay turned on"

  - platform: restart
    name: "${friendly_name} Restart"
```

## Home Assistant Integration

### Native API (Recommended)

```yaml
api:
  encryption:
    key: !secret api_key
  reboot_timeout: 15min

  # Custom services callable from HA
  services:
    - service: set_led_color
      variables:
        r: int
        g: int
        b: int
      then:
        - light.turn_on:
            id: status_led
            red: !lambda 'return r / 255.0;'
            green: !lambda 'return g / 255.0;'
            blue: !lambda 'return b / 255.0;'
```

### Trigger HA Events

```yaml
on_press:
  - homeassistant.event:
      event: esphome.button_pressed
      data:
        device: "${device_name}"
```

### Call HA Services

```yaml
on_press:
  - homeassistant.service:
      service: light.toggle
      data:
        entity_id: light.living_room
```

## OTA Updates

**Note**: Changed in 2024.6.0 - now platform-based:

```yaml
ota:
  - platform: esphome
    password: !secret ota_password
    on_begin:
      then:
        - logger.log: "OTA starting..."
    on_end:
      then:
        - logger.log: "OTA complete!"
```

## Debug and Monitoring

```yaml
debug:
  update_interval: 5s

sensor:
  - platform: debug
    free:
      name: "Heap Free"
    loop_time:
      name: "Loop Time"

text_sensor:
  - platform: debug
    device:
      name: "Device Info"
    reset_reason:
      name: "Reset Reason"
```

## Device-Specific Guides

### RATGDO (Garage Door)

See `devices/ratgdo.md` for complete configuration.

```yaml
substitutions:
  id_prefix: garage
  friendly_name: "Garage Door"

packages:
  ratgdo:
    url: https://github.com/ratgdo/esphome-ratgdo
    ref: main
    files: [base.yaml]
    refresh: 1s
```

### Waveshare 86-Panel (ESP32-P4)

See `devices/waveshare-86.md` for touch panel configuration with LVGL.

## GPIO Gotchas

### ESP32 Strapping Pins (Avoid)

- GPIO0, GPIO2, GPIO5, GPIO12, GPIO15

### Input-Only Pins (ESP32)

- GPIO34, GPIO35, GPIO36, GPIO39 - cannot be outputs

### Boot Glitch

Outputs may briefly toggle during boot. For safety-critical:
```yaml
switch:
  - platform: gpio
    pin: GPIO5
    restore_mode: ALWAYS_OFF
```

## Common Issues

### WiFi Problems

```yaml
wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  fast_connect: true  # Skip scan if BSSID known
  power_save_mode: none  # For stability
  ap:
    ssid: "${name} Fallback"
    password: "fallback123"
```

- **Mesh networks**: Set router to 20MHz channel width
- **Special chars in password**: Avoid `\`, `'`, `"`

### Memory Issues (ESP8266)

- Use `logger: level: INFO` (not DEBUG)
- Set `baud_rate: 0` to disable serial logging
- Consider ESP32-C3 minimum for new projects

## Secrets Management

**secrets.yaml** (never commit):
```yaml
wifi_ssid: "MyNetwork"
wifi_password: "password"
api_key: "base64key=="
ota_password: "otapass"
```

**For remote packages**, use substitutions:
```yaml
# Remote package uses ${wifi_ssid}
# Local config overrides:
substitutions:
  wifi_ssid: !secret wifi_ssid
```

## CLI Commands

```bash
# Validate config
esphome config device.yaml

# Compile only
esphome compile device.yaml

# Upload and monitor
esphome run device.yaml

# View logs only
esphome logs device.yaml
```

## Reference Files

- `reference/configuration.md` - Full YAML structure reference
- `reference/lvgl.md` - Display and touch integration
- `devices/ratgdo.md` - Garage door controller
- `devices/waveshare-86.md` - ESP32-P4 touch panels

## External Resources

- **Getting Started**: https://esphome.io/guides/getting_started_command_line.html
- **All Components**: https://esphome.io/components/index.html
- **FAQ/Troubleshooting**: https://esphome.io/guides/faq.html
- **LVGL Graphics**: https://esphome.io/components/lvgl/
