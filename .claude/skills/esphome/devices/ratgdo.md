# RATGDO Garage Door Controller

ESP-based controller for garage door openers with native ESPHome support.

## Supported Openers

| Type | Learn Button | Features |
|------|-------------|----------|
| Security+ 2.0 | Yellow | Full digital: position, obstruction, light |
| Security+ 1.0 | Purple/Orange/Red | Partial support |
| Dry Contact | Any | Relay-based, requires external sensors |

## Basic Configuration

```yaml
substitutions:
  id_prefix: garage
  friendly_name: "Garage Door"
  uart_tx_pin: D1
  uart_rx_pin: D2
  input_obst_pin: D7
  status_door_pin: D0
  status_obstruction_pin: D8
  dry_contact_open_pin: D5
  dry_contact_close_pin: D6
  dry_contact_light_pin: D3

packages:
  ratgdo:
    url: https://github.com/ratgdo/esphome-ratgdo
    ref: main
    files: [base.yaml]
    refresh: 1s

esphome:
  name: ${id_prefix}
  friendly_name: ${friendly_name}

esp8266:
  board: d1_mini
  restore_from_flash: true

api:
wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  ap:
    ssid: "${id_prefix}"

web_server:
logger:
```

## Entities Created

- `cover.garage_door` - Door control with position
- `binary_sensor.obstruction` - Obstruction beam
- `sensor.door_position` - Position percentage (after calibration)
- `switch.light` - Garage light
- `switch.lock` - Wireless remote lockout
- `button.sync` - Re-sync with opener

## Calibration

**Required for position tracking**: Open and close door once completely without stopping.

## Home Assistant Automations

### Auto-Close After Timeout

```yaml
automation:
  - alias: "Garage Auto-Close"
    triggers:
      - trigger: state
        entity_id: cover.garage_door
        to: "open"
        for:
          minutes: 30
    conditions:
      - condition: state
        entity_id: input_boolean.garage_auto_close
        state: "on"
    actions:
      - action: cover.close_cover
        target:
          entity_id: cover.garage_door

  - alias: "Garage Close Notification"
    triggers:
      - trigger: state
        entity_id: cover.garage_door
        to: "open"
        for:
          minutes: 25
    actions:
      - action: notify.mobile_app
        data:
          message: "Garage will auto-close in 5 minutes"
          data:
            actions:
              - action: CANCEL_GARAGE_CLOSE
                title: "Keep Open"
```

### Obstruction Alert

```yaml
automation:
  - alias: "Garage Obstruction Alert"
    triggers:
      - trigger: state
        entity_id: binary_sensor.obstruction
        to: "on"
    actions:
      - action: notify.mobile_app
        data:
          message: "Garage door obstruction detected!"
          data:
            tag: garage-obstruction
            priority: high
```

### Close at Night

```yaml
automation:
  - alias: "Close Garage at Night"
    triggers:
      - trigger: time
        at: "22:00:00"
    conditions:
      - condition: state
        entity_id: cover.garage_door
        state: "open"
    actions:
      - action: notify.mobile_app
        data:
          message: "Closing garage door for the night"
      - action: cover.close_cover
        target:
          entity_id: cover.garage_door
```

### Presence-Based Control

```yaml
automation:
  - alias: "Close Garage When Leaving"
    triggers:
      - trigger: state
        entity_id: person.john
        from: "home"
        for:
          minutes: 5
    conditions:
      - condition: state
        entity_id: cover.garage_door
        state: "open"
    actions:
      - action: cover.close_cover
        target:
          entity_id: cover.garage_door
```

## Dry Contact Setup

For non-Security+ openers, you need external sensors:

```yaml
# Add to config after packages
binary_sensor:
  - platform: gpio
    pin:
      number: GPIO14
      mode: INPUT_PULLUP
    name: "Door Closed Sensor"
    device_class: garage_door
    filters:
      - delayed_on: 100ms
      - delayed_off: 100ms
```

## Gotchas

1. **Calibration required** - Position won't work until full open/close cycle
2. **Obstruction sensor voltage** - Only 5-16V sensors (>18V damages board)
3. **Security+ 2.0 only** - Full features require yellow learn button opener
4. **WiFi required for control** - No local button on board

## Resources

- **Official Site**: https://paulwieland.github.io/ratgdo/
- **ESPHome Firmware**: https://github.com/ratgdo/esphome-ratgdo
- **Web Installer**: https://ratgdo.github.io/esphome-ratgdo/
- **Wiring Guide**: https://paulwieland.github.io/ratgdo/03_wiring.html
