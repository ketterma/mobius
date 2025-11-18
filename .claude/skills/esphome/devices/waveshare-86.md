# Waveshare 86-Panel (ESP32-P4)

Wall-mountable touch panel displays using the ESP32-P4 chip with LVGL graphics.

## Hardware Overview

### ESP32-P4 Capabilities

- **CPU**: Dual-core 400 MHz RISC-V
- **Memory**: 768 KB SRAM, up to 32 MB PSRAM
- **Display**: MIPI-DSI (up to 1080p)
- **No built-in WiFi** - Requires companion chip (ESP32-C6)

### Waveshare Models

**ESP32-P4-WIFI6-Touch-LCD-4B** (~$40-50)
- 4" IPS, 720x720, 5-point capacitive touch
- MIPI CSI camera connector
- 28-pin GPIO header

**ESP32-P4-86-Panel-ETH-2RO** (~$50-65)
- Same display
- 2x 10A relays
- RS485, 10/100M Ethernet
- 6-30V DC input

**Installation**: Requires 86-type box, depth >= 33mm (35mm for Ethernet)

## ESPHome Configuration

**Note**: ESP32-P4 requires ESP-IDF framework (Arduino not supported).

```yaml
esphome:
  name: wall-panel
  friendly_name: "Wall Panel"

esp32:
  board: esp32-p4-function-ev-board
  variant: esp32p4
  framework:
    type: esp-idf
    version: 5.3.2

# Required for ESP32-P4
esp_ldo:
  - id: ldo_3v3
    channel: 1
    voltage: 3.3V

psram:
  mode: octal
  speed: 80MHz
```

## LVGL Display Setup

```yaml
spi:
  clk_pin: GPIO12
  mosi_pin: GPIO11

display:
  - platform: ili9xxx
    model: ST7789V
    id: my_display
    cs_pin: GPIO10
    dc_pin: GPIO9
    dimensions:
      height: 720
      width: 720
    auto_clear_enabled: false  # Required for LVGL
    update_interval: never     # LVGL handles updates

i2c:
  sda: GPIO6
  scl: GPIO7

touchscreen:
  - platform: gt911
    id: my_touch

lvgl:
  displays:
    - my_display
  touchscreens:
    - my_touch
```

## LVGL Widgets

### Basic Page Layout

```yaml
lvgl:
  pages:
    - id: main_page
      widgets:
        # Header
        - label:
            text: "Living Room"
            align: TOP_MID
            y: 20
            text_font: montserrat_28

        # Temperature display
        - label:
            id: temp_label
            text: "--°C"
            align: CENTER
            text_font: montserrat_48

        # Control buttons
        - button:
            align: BOTTOM_LEFT
            x: 20
            y: -20
            width: 100
            height: 50
            widgets:
              - label:
                  text: "Off"
                  align: CENTER
            on_press:
              - homeassistant.service:
                  service: light.turn_off
                  data:
                    entity_id: light.living_room

        - button:
            align: BOTTOM_RIGHT
            x: -20
            y: -20
            width: 100
            height: 50
            widgets:
              - label:
                  text: "On"
                  align: CENTER
            on_press:
              - homeassistant.service:
                  service: light.turn_on
                  data:
                    entity_id: light.living_room
```

### Slider Control

```yaml
- slider:
    id: brightness_slider
    align: CENTER
    y: 50
    width: 200
    min_value: 0
    max_value: 255
    on_value:
      - homeassistant.service:
          service: light.turn_on
          data:
            entity_id: light.living_room
            brightness: !lambda 'return (int)x;'
```

### Arc (Thermostat)

```yaml
- arc:
    id: temp_arc
    align: CENTER
    width: 200
    height: 200
    min_value: 16
    max_value: 30
    value: 21
    on_value:
      - homeassistant.service:
          service: climate.set_temperature
          data:
            entity_id: climate.thermostat
            temperature: !lambda 'return x;'
```

### Update from Home Assistant

```yaml
sensor:
  - platform: homeassistant
    id: living_room_temp
    entity_id: sensor.living_room_temperature
    on_value:
      - lvgl.label.update:
          id: temp_label
          text: !lambda 'return str(x, 1) + "°C";'
```

## Page Navigation

```yaml
lvgl:
  on_idle:
    timeout: 30s
    then:
      - lvgl.page.show: screensaver_page
        animation: FADE_IN

# Physical button to change pages
binary_sensor:
  - platform: gpio
    pin: GPIO0
    on_press:
      - lvgl.page.next:
          animation: MOVE_LEFT
          time: 300ms
```

## Screensaver

```yaml
pages:
  - id: screensaver_page
    widgets:
      - label:
          text: ""  # Blank screen

lvgl:
  on_idle:
    timeout: 60s
    then:
      - lvgl.page.show: screensaver_page
      - light.turn_off:
          id: backlight
```

## Relay Control (ETH-2RO Model)

```yaml
switch:
  - platform: gpio
    pin: GPIO40
    name: "Relay 1"
    id: relay_1

  - platform: gpio
    pin: GPIO41
    name: "Relay 2"
    id: relay_2
```

## Theming

```yaml
lvgl:
  theme:
    btn:
      bg_color: 0x2196F3
      text_color: 0xFFFFFF
      radius: 8
    label:
      text_color: 0xFFFFFF
  style_definitions:
    - id: header_style
      text_font: montserrat_28
      text_color: 0xFFFFFF
```

## Memory Considerations

LVGL is memory-intensive:

```yaml
# Reduce buffer size if needed
lvgl:
  buffer_size: 25%

# Use smaller fonts
# Limit number of pages
# Avoid large images
```

## Gotchas

1. **ESP-IDF only** - Arduino framework not supported for ESP32-P4
2. **No WiFi built-in** - Need companion chip or Ethernet model
3. **PSRAM required** - LVGL needs external RAM
4. **Display config critical** - Must set `auto_clear_enabled: false` and `update_interval: never`
5. **Font memory** - Custom fonts consume significant RAM

## Resources

- **ESPHome LVGL**: https://esphome.io/components/lvgl/
- **LVGL Widgets**: https://esphome.io/components/lvgl/widgets/
- **Waveshare Wiki**: https://www.waveshare.com/wiki/ESP32-P4-WIFI6-Touch-LCD-4B
- **ESP32-P4 Datasheet**: https://www.espressif.com/en/products/socs/esp32-p4
