use crate::{CapabilityRange, Channel, ChannelKind, ColorComponent, FixtureProject, WheelKind};
use serde_json::{Map, Value, json};
use std::collections::HashMap;

pub fn export_ofl(fixture: &FixtureProject) -> Value {
    let export_date = provenance_date(&fixture.provenance.imported_at);
    let mut available_channels = Map::new();
    for channel in fixture
        .channels
        .iter()
        .filter(|item| item.fine_of.is_none())
    {
        let mut capabilities: Vec<Value> = if channel.ranges.is_empty() {
            vec![capability(channel, None)]
        } else {
            channel
                .ranges
                .iter()
                .map(|range| capability(channel, Some(range)))
                .collect()
        };
        let mut object = Map::new();
        if capabilities.len() == 1 {
            let mut single = capabilities.remove(0);
            single
                .as_object_mut()
                .expect("capability object")
                .remove("dmxRange");
            object.insert("capability".to_owned(), single);
        } else {
            object.insert("capabilities".to_owned(), Value::Array(capabilities));
        }
        if let Some(fine) = fixture
            .channels
            .iter()
            .find(|item| item.fine_of.as_deref() == Some(channel.id.as_str()))
        {
            object.insert("fineChannelAliases".to_owned(), json!([fine.id]));
            object.insert("dmxValueResolution".to_owned(), json!("16bit"));
        }
        available_channels.insert(channel.id.clone(), Value::Object(object));
    }

    let mut modes = Vec::new();
    for mode in &fixture.modes {
        for dmx_break in 1..=mode.breaks.max(1) {
            let channels: Vec<Value> = mode
                .channels
                .iter()
                .filter(|assignment| assignment.dmx_break == dmx_break)
                .map(|assignment| json!(assignment.channel_id))
                .collect();
            if channels.is_empty() {
                continue;
            }
            let mut exported = Map::new();
            exported.insert(
                "name".to_owned(),
                json!(if mode.breaks > 1 {
                    format!("{} — Universe {}", mode.name, dmx_break)
                } else {
                    mode.name.clone()
                }),
            );
            if !mode.short_name.is_empty() {
                exported.insert("shortName".to_owned(), json!(mode.short_name));
            }
            exported.insert("channels".to_owned(), Value::Array(channels));
            modes.push(Value::Object(exported));
        }
    }

    let categories = if fixture.identity.categories.is_empty() {
        vec![if fixture.geometry.yoke || fixture.geometry.head {
            "Moving Head".to_owned()
        } else {
            "Other".to_owned()
        }]
    } else {
        fixture.identity.categories.clone()
    };
    let mut root = json!({
        "$schema": "https://raw.githubusercontent.com/OpenLightingProject/open-fixture-library/master/schemas/fixture.json",
        "name": fixture.identity.model,
        "shortName": if fixture.identity.short_name.is_empty() { fixture.identity.model.clone() } else { fixture.identity.short_name.clone() },
        "categories": categories,
        "meta": {
            "authors": ["DMXtract"],
            "createDate": export_date,
            "lastModifyDate": export_date
        },
        "availableChannels": available_channels,
        "modes": modes
    });

    if let Some(physical) = ofl_physical(fixture) {
        root["physical"] = physical;
    }
    if let Some(wheels) = ofl_wheels(fixture) {
        root["wheels"] = wheels;
    }
    if let Some(matrix) = &fixture.matrix {
        root["matrix"] = json!({ "pixelCount": [matrix.x, matrix.y, matrix.z.max(1)] });
        let lookup: HashMap<&str, &Channel> = fixture
            .channels
            .iter()
            .map(|channel| (channel.id.as_str(), channel))
            .collect();
        let mut templates = Map::new();
        for id in &matrix.template_channels {
            if let Some(channel) = lookup.get(id.as_str()) {
                templates.insert(
                    channel.id.clone(),
                    json!({ "capability": capability(channel, None) }),
                );
            }
        }
        if !templates.is_empty() {
            root["templateChannels"] = Value::Object(templates);
        }
    }
    root
}

fn capability(channel: &Channel, range: Option<&CapabilityRange>) -> Value {
    let requested_kind = range
        .and_then(|item| item.capability)
        .unwrap_or(channel.kind);
    let mut output = Map::new();
    let capability_type = if matches!(
        requested_kind,
        ChannelKind::ColorWheel | ChannelKind::GoboWheel
    ) && range.and_then(|item| item.wheel_slot).is_none()
    {
        "Generic"
    } else {
        ofl_kind(requested_kind)
    };
    output.insert("type".to_owned(), json!(capability_type));
    output.insert(
        "comment".to_owned(),
        json!(range.map_or(channel.name.as_str(), |item| item.name.as_str())),
    );
    if let Some(range) = range {
        output.insert("dmxRange".to_owned(), json!([range.start, range.end]));
    }
    if capability_type == "ColorIntensity" {
        output.insert(
            "color".to_owned(),
            json!(channel.color.map(ofl_color).unwrap_or("White")),
        );
    }
    if capability_type == "ShutterStrobe" {
        let name = range
            .map_or(channel.name.as_str(), |item| item.name.as_str())
            .to_lowercase();
        let effect = if name.contains("off") || name.contains("closed") {
            "Closed"
        } else if name.contains("on") || name.contains("open") {
            "Open"
        } else {
            "Strobe"
        };
        output.insert("shutterEffect".to_owned(), json!(effect));
    }
    if capability_type == "WheelSlot"
        && let Some(slot) = range.and_then(|item| item.wheel_slot)
    {
        output.insert("slotNumber".to_owned(), json!(slot));
        if let Some(wheel) = &channel.wheel_id {
            output.insert("wheel".to_owned(), json!(wheel));
        }
    }
    Value::Object(output)
}

fn ofl_physical(fixture: &FixtureProject) -> Option<Value> {
    let physical = &fixture.physical;
    let mut output = Map::new();
    if let (Some(width), Some(height), Some(depth)) =
        (physical.width_mm, physical.height_mm, physical.depth_mm)
    {
        output.insert("dimensions".to_owned(), json!([width, height, depth]));
    }
    if let Some(weight) = physical.weight_kg {
        output.insert("weight".to_owned(), json!(weight));
    }
    if let Some(power) = physical.power_w {
        output.insert("power".to_owned(), json!(power));
    }
    if let (Some(minimum), Some(maximum)) = (physical.lens_min_degrees, physical.lens_max_degrees) {
        output.insert(
            "lens".to_owned(),
            json!({ "degreesMinMax": [minimum, maximum] }),
        );
    }
    (!output.is_empty()).then_some(Value::Object(output))
}

fn ofl_wheels(fixture: &FixtureProject) -> Option<Value> {
    let mut wheels = Map::new();
    for wheel in &fixture.wheels {
        let slots: Vec<Value> = wheel
            .slots
            .iter()
            .map(|slot| {
                if slot.number == 1 && slot.name.to_lowercase().contains("open") {
                    json!({ "type": "Open" })
                } else {
                    match wheel.kind {
                        WheelKind::Color => {
                            let mut value = json!({ "type": "Color", "name": slot.name });
                            if let Some(color) = &slot.color {
                                value["colors"] = json!([color]);
                            }
                            value
                        }
                        WheelKind::Prism => json!({ "type": "Prism", "name": slot.name }),
                        _ => json!({ "type": "Gobo", "name": slot.name }),
                    }
                }
            })
            .collect();
        if slots.len() >= 2 {
            wheels.insert(wheel.id.clone(), json!({ "slots": slots }));
        }
    }
    (!wheels.is_empty()).then_some(Value::Object(wheels))
}

fn provenance_date(value: &str) -> &str {
    let Some(date) = value.get(0..10) else {
        return "1970-01-01";
    };
    let bytes = date.as_bytes();
    if bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit())
    {
        date
    } else {
        "1970-01-01"
    }
}

fn ofl_kind(kind: ChannelKind) -> &'static str {
    match kind {
        ChannelKind::Intensity => "Intensity",
        ChannelKind::ColorIntensity => "ColorIntensity",
        ChannelKind::Shutter | ChannelKind::Strobe => "ShutterStrobe",
        ChannelKind::ColorWheel | ChannelKind::GoboWheel => "WheelSlot",
        ChannelKind::Prism => "Prism",
        ChannelKind::Maintenance => "Maintenance",
        _ => "Generic",
    }
}

fn ofl_color(color: ColorComponent) -> &'static str {
    match color {
        ColorComponent::Red => "Red",
        ColorComponent::Green => "Green",
        ColorComponent::Blue => "Blue",
        ColorComponent::White => "White",
        ColorComponent::Amber => "Amber",
        ColorComponent::Uv => "UV",
        ColorComponent::Cyan => "Cyan",
        ColorComponent::Magenta => "Magenta",
        ColorComponent::Yellow => "Yellow",
        ColorComponent::Lime => "Lime",
        ColorComponent::Indigo => "Indigo",
    }
}
