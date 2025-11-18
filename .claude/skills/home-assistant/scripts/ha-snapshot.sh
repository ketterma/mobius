#!/bin/bash
# Fetch camera snapshot from Home Assistant
# Usage: ha-snapshot.sh <camera_entity_id> [output_file]
#
# Examples:
#   ha-snapshot.sh camera.g4_doorbell_high
#   ha-snapshot.sh camera.g4_doorbell_high /tmp/doorbell.jpg
#
# Requires: HASS_SERVER and HASS_TOKEN environment variables
# Load from .env: source .env && ./ha-snapshot.sh ...

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <camera_entity_id> [output_file]"
    echo ""
    echo "Examples:"
    echo "  $0 camera.g4_doorbell_high"
    echo "  $0 camera.living_room_high /tmp/living_room.jpg"
    exit 1
fi

CAMERA_ID="$1"
OUTPUT_FILE="${2:-/tmp/${CAMERA_ID#camera.}_$(date +%Y%m%d_%H%M%S).jpg}"

if [ -z "$HASS_SERVER" ] || [ -z "$HASS_TOKEN" ]; then
    echo "Error: HASS_SERVER and HASS_TOKEN must be set"
    echo "Run: source .env"
    exit 1
fi

curl -s -o "$OUTPUT_FILE" \
    -H "Authorization: Bearer $HASS_TOKEN" \
    "$HASS_SERVER/api/camera_proxy/$CAMERA_ID"

if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    echo "Saved: $OUTPUT_FILE"
    file "$OUTPUT_FILE"
else
    echo "Error: Failed to fetch snapshot"
    rm -f "$OUTPUT_FILE"
    exit 1
fi
