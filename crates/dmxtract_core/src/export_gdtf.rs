use crate::{Channel, ChannelKind, FixtureProject, WheelKind};
use std::collections::{BTreeMap, BTreeSet};
use std::io::{Cursor, Write};
use uuid::Uuid;
use zip::{CompressionMethod, ZipWriter, write::SimpleFileOptions};

pub struct GdtfExport {
    pub bytes: Vec<u8>,
    pub description_xml: String,
}

pub fn export_gdtf(fixture: &FixtureProject) -> Result<GdtfExport, crate::CoreError> {
    let description_xml = build_description(fixture);
    let mut cursor = Cursor::new(Vec::new());
    {
        let mut archive = ZipWriter::new(&mut cursor);
        archive.start_file(
            "description.xml",
            SimpleFileOptions::default().compression_method(CompressionMethod::Deflated),
        )?;
        archive.write_all(description_xml.as_bytes())?;
        archive.finish()?;
    }
    Ok(GdtfExport {
        bytes: cursor.into_inner(),
        description_xml,
    })
}

fn build_description(fixture: &FixtureProject) -> String {
    let fixture_uuid = Uuid::new_v5(
        &Uuid::NAMESPACE_URL,
        format!("dmxtract:{}", fixture.id).as_bytes(),
    );
    let mut xml = String::new();
    xml.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<GDTF DataVersion=\"1.2\">\n");
    xml.push_str(&format!("  <FixtureType Name=\"{}\" ShortName=\"{}\" LongName=\"{} {}\" Manufacturer=\"{}\" Description=\"Generated locally by DMXtract; extracted from manual\" FixtureTypeID=\"{}\" RefFT=\"\">\n",
        esc(&fixture.identity.model), esc(short_name(fixture)), esc(&fixture.identity.manufacturer), esc(&fixture.identity.model), esc(&fixture.identity.manufacturer), fixture_uuid));
    let mut features: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    for channel in fixture
        .channels
        .iter()
        .filter(|channel| channel.fine_of.is_none())
    {
        let channel_feature = feature(channel);
        let (group, item) = channel_feature
            .split_once('.')
            .unwrap_or((channel_feature, "Control"));
        features.entry(group).or_default().insert(item);
    }
    xml.push_str("    <AttributeDefinitions>\n      <ActivationGroups/>\n      <FeatureGroups>\n");
    for (group, items) in features {
        xml.push_str(&format!(
            "        <FeatureGroup Name=\"{}\" Pretty=\"{}\">",
            esc(group),
            esc(group)
        ));
        for item in items {
            xml.push_str(&format!("<Feature Name=\"{}\"/>", esc(item)));
        }
        xml.push_str("</FeatureGroup>\n");
    }
    xml.push_str("      </FeatureGroups>\n      <Attributes>\n");
    let mut declared_attributes = BTreeSet::new();
    for channel in &fixture.channels {
        if channel.fine_of.is_some() {
            continue;
        }
        let attribute = attribute_name(channel);
        if !declared_attributes.insert(attribute.clone()) {
            continue;
        }
        xml.push_str(&format!("        <Attribute Name=\"{}\" Pretty=\"{}\" Feature=\"{}\" PhysicalUnit=\"None\" Color=\"0.3127,0.3290,100.0\"/>\n", esc(&attribute), esc(&channel.name), esc(feature(channel))));
    }
    xml.push_str("      </Attributes>\n    </AttributeDefinitions>\n");

    xml.push_str("    <Wheels>\n");
    for wheel in &fixture.wheels {
        xml.push_str(&format!("      <Wheel Name=\"{}\">\n", esc(&wheel.name)));
        for slot in &wheel.slots {
            let color = slot
                .color
                .as_deref()
                .and_then(hex_to_gdtf)
                .unwrap_or("0.3127,0.3290,100.0".to_owned());
            let media = if wheel.kind == WheelKind::Gobo {
                slot.media_file.as_deref().unwrap_or("")
            } else {
                ""
            };
            xml.push_str(&format!(
                "        <Slot Name=\"{}\" Color=\"{}\" MediaFileName=\"{}\"/>\n",
                esc(&slot.name),
                color,
                esc(media)
            ));
        }
        xml.push_str("      </Wheel>\n");
    }
    xml.push_str("    </Wheels>\n");

    xml.push_str("    <PhysicalDescriptions><Emitters/><Filters/><ColorSpace Mode=\"sRGB\" Description=\"Generic sRGB\"/><DMXProfiles/><CRIs/><Connectors/></PhysicalDescriptions>\n");
    xml.push_str("    <Models><Model Name=\"GenericBody\" Length=\"0.3\" Width=\"0.3\" Height=\"0.3\" PrimitiveType=\"Cube\" File=\"\"/></Models>\n");
    xml.push_str("    <Geometries><Geometry Name=\"Body\" Model=\"GenericBody\" Position=\"{1,0,0,0}{0,1,0,0}{0,0,1,0}{0,0,0,1}\">\n");
    if fixture
        .matrix
        .as_ref()
        .is_some_and(|matrix| !matrix.pixels.is_empty())
    {
        for pixel in &fixture.matrix.as_ref().unwrap().pixels {
            xml.push_str(&format!("      <Beam Name=\"{}\" Model=\"\" Position=\"{{1,0,0,0}}{{0,1,0,0}}{{0,0,1,0}}{{{},{},0,1}}\" LampType=\"LED\" PowerConsumption=\"0\" LuminousFlux=\"0\" ColorTemperature=\"6500\" BeamAngle=\"{}\" FieldAngle=\"{}\" BeamRadius=\"0.01\" BeamType=\"Wash\" ColorRenderingIndex=\"90\" EmitterSpectrum=\"\"/>\n", esc(&pixel.id), f64::from(pixel.x) / 10.0, f64::from(pixel.y) / 10.0, beam_angle(fixture), beam_angle(fixture)));
        }
    } else {
        xml.push_str(&format!("      <Beam Name=\"Beam\" Model=\"\" Position=\"{{1,0,0,0}}{{0,1,0,0}}{{0,0,1,0}}{{0,0,0,1}}\" LampType=\"LED\" PowerConsumption=\"{}\" LuminousFlux=\"0\" ColorTemperature=\"6500\" BeamAngle=\"{}\" FieldAngle=\"{}\" BeamRadius=\"0.05\" BeamType=\"Wash\" ColorRenderingIndex=\"90\" EmitterSpectrum=\"\"/>\n", fixture.physical.power_w.unwrap_or(0.0), beam_angle(fixture), beam_angle(fixture)));
    }
    xml.push_str("    </Geometry></Geometries>\n    <DMXModes>\n");
    for mode in &fixture.modes {
        xml.push_str(&format!("      <DMXMode Name=\"{}\" Description=\"{} controls\" Geometry=\"Body\">\n        <DMXChannels>\n", esc(&mode.name), mode.channels.len()));
        for assignment in &mode.channels {
            let Some(channel) = fixture
                .channels
                .iter()
                .find(|channel| channel.id == assignment.channel_id)
            else {
                continue;
            };
            let offset = if let Some(coarse_id) = &channel.fine_of {
                let coarse_offset = mode
                    .channels
                    .iter()
                    .find(|candidate| &candidate.channel_id == coarse_id)
                    .map(|candidate| candidate.offset)
                    .unwrap_or(assignment.offset);
                format!("{coarse_offset},{}", assignment.offset)
            } else {
                assignment.offset.to_string()
            };
            if channel.fine_of.is_some() {
                continue;
            }
            xml.push_str(&format!("          <DMXChannel DMXBreak=\"{}\" Offset=\"{}\" Default=\"0/1\" Highlight=\"None\" Geometry=\"Beam\" InitialFunction=\"{}.{}.{}\">\n            <LogicalChannel Attribute=\"{}\" Snap=\"No\" Master=\"None\" MibFade=\"0\" DMXChangeTimeLimit=\"0\">\n", assignment.dmx_break, offset, esc(&mode.name), esc(&channel.name), esc(&channel.name), esc(&attribute_name(channel))));
            let ranges = if channel.ranges.is_empty() {
                vec![(0, 255, channel.name.as_str())]
            } else {
                channel
                    .ranges
                    .iter()
                    .map(|range| (range.start, range.end, range.name.as_str()))
                    .collect()
            };
            for (index, (start, end, name)) in ranges.iter().enumerate() {
                let wheel = channel
                    .wheel_id
                    .as_ref()
                    .and_then(|id| fixture.wheels.iter().find(|wheel| &wheel.id == id))
                    .map(|wheel| wheel.name.as_str())
                    .unwrap_or("");
                xml.push_str(&format!("              <ChannelFunction Name=\"{}\" Attribute=\"{}\" OriginalAttribute=\"{}\" DMXFrom=\"{}/1\" Default=\"0/1\" PhysicalFrom=\"0\" PhysicalTo=\"1\" RealFade=\"0\" RealAcceleration=\"0\" Wheel=\"{}\" Emitter=\"\" Filter=\"\" ColorSpace=\"\" Gamut=\"\" ModeMaster=\"None\" ModeFrom=\"0/1\" ModeTo=\"255/1\">\n                <ChannelSet Name=\"{}\" DMXFrom=\"{}/1\" PhysicalFrom=\"{}\" PhysicalTo=\"{}\" WheelSlotIndex=\"{}\"/>\n              </ChannelFunction>\n", esc(name), esc(&attribute_name(channel)), esc(&channel.name), start, esc(wheel), esc(name), start, start, end, index + 1));
            }
            xml.push_str("            </LogicalChannel>\n          </DMXChannel>\n");
        }
        xml.push_str(
            "        </DMXChannels>\n        <Relations/>\n        <FTMacros/>\n      </DMXMode>\n",
        );
    }
    xml.push_str("    </DMXModes>\n    <Revisions/>\n    <Presets/>\n    <Protocols/>\n  </FixtureType>\n</GDTF>\n");
    xml
}

fn short_name(fixture: &FixtureProject) -> &str {
    if fixture.identity.short_name.is_empty() {
        &fixture.identity.model
    } else {
        &fixture.identity.short_name
    }
}
fn beam_angle(fixture: &FixtureProject) -> f64 {
    fixture
        .physical
        .lens_max_degrees
        .or(fixture.physical.lens_min_degrees)
        .unwrap_or(25.0)
}
fn feature(channel: &Channel) -> &str {
    if let Some(value) = channel
        .gdtf_feature
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        return value;
    }
    match channel.kind {
        ChannelKind::Intensity => "Dimmer.Dimmer",
        ChannelKind::Pan | ChannelKind::Tilt => "Position.PanTilt",
        ChannelKind::ColorIntensity => "Color.RGB",
        ChannelKind::ColorWheel => "Color.Color",
        ChannelKind::GoboWheel | ChannelKind::GoboRotation => "Gobo.Gobo",
        ChannelKind::Focus | ChannelKind::Zoom => "Focus.Focus",
        ChannelKind::Frost | ChannelKind::Prism => "Beam.Beam",
        _ => "Control.Control",
    }
}
fn attribute_name(channel: &Channel) -> String {
    channel
        .gdtf_attribute
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(&channel.name)
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || *character == '_')
        .collect::<String>()
        .chars()
        .take(32)
        .collect::<String>()
}
fn esc(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
fn hex_to_gdtf(value: &str) -> Option<String> {
    let hex = value.trim_start_matches('#');
    if hex.len() != 6 {
        return None;
    }
    let red = u8::from_str_radix(&hex[0..2], 16).ok()?;
    let green = u8::from_str_radix(&hex[2..4], 16).ok()?;
    let blue = u8::from_str_radix(&hex[4..6], 16).ok()?;
    let sum = f64::from(red) + f64::from(green) + f64::from(blue);
    if sum == 0.0 {
        return Some("0.3127,0.3290,0.0".to_owned());
    }
    Some(format!(
        "{:.4},{:.4},{:.1}",
        f64::from(red) / sum,
        f64::from(green) / sum,
        sum / 7.65
    ))
}
