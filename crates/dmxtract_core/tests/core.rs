use dmxtract_core::*;
use std::io::{Cursor, Read};

fn fixture() -> FixtureProject {
    FixtureProject {
        schema: FIXTURE_SCHEMA_ID.to_owned(),
        schema_version: 1,
        id: "betopper-lb150".to_owned(),
        identity: Identity {
            manufacturer: "Betopper".to_owned(),
            model: "LB150".to_owned(),
            short_name: "LB150".to_owned(),
            categories: vec!["Moving Head".to_owned()],
            confidence: Confidence::default(),
        },
        physical: Physical {
            power_w: Some(150.0),
            lens_min_degrees: Some(13.0),
            lens_max_degrees: Some(13.0),
            ..Default::default()
        },
        provenance: Provenance {
            source_type: "manual".to_owned(),
            source_name: "406-15012-002D.pdf".to_owned(),
            ..Default::default()
        },
        channels: vec![
            Channel {
                id: "dimmer".to_owned(),
                name: "Dimmer".to_owned(),
                kind: ChannelKind::Intensity,
                gdtf_attribute: Some("Dimmer".to_owned()),
                gdtf_feature: Some("Dimmer.Dimmer".to_owned()),
                color: None,
                fine_of: None,
                wheel_id: None,
                ranges: vec![CapabilityRange {
                    start: 0,
                    end: 255,
                    name: "Brightness".to_owned(),
                    capability: None,
                    wheel_slot: None,
                    safety: SafetyClass::Normal,
                    confidence: Confidence::default(),
                    source: None,
                }],
                confidence: Confidence::default(),
                source: None,
            },
            Channel {
                id: "strobe".to_owned(),
                name: "Strobe".to_owned(),
                kind: ChannelKind::Strobe,
                gdtf_attribute: Some("Shutter1Strobe".to_owned()),
                gdtf_feature: Some("Beam.Beam".to_owned()),
                color: None,
                fine_of: None,
                wheel_id: None,
                ranges: vec![
                    CapabilityRange {
                        start: 0,
                        end: 9,
                        name: "Open".to_owned(),
                        capability: None,
                        wheel_slot: None,
                        safety: SafetyClass::Normal,
                        confidence: Confidence::default(),
                        source: None,
                    },
                    CapabilityRange {
                        start: 10,
                        end: 255,
                        name: "Flash speed".to_owned(),
                        capability: None,
                        wheel_slot: None,
                        safety: SafetyClass::Strobe,
                        confidence: Confidence::default(),
                        source: None,
                    },
                ],
                confidence: Confidence::default(),
                source: None,
            },
        ],
        modes: vec![Mode {
            id: "full".to_owned(),
            name: "Full control".to_owned(),
            short_name: "2ch".to_owned(),
            breaks: 1,
            channels: vec![
                ChannelAssignment {
                    channel_id: "dimmer".to_owned(),
                    offset: 1,
                    dmx_break: 1,
                },
                ChannelAssignment {
                    channel_id: "strobe".to_owned(),
                    offset: 2,
                    dmx_break: 1,
                },
            ],
            confidence: Confidence::default(),
        }],
        wheels: vec![],
        matrix: None,
        geometry: Geometry::default(),
    }
}

#[test]
fn validates_and_exports_ofl() {
    let fixture = fixture();
    assert!(validate_fixture(&fixture).is_empty());
    let output = export_ofl(&fixture);
    assert_eq!(output["name"], "LB150");
    assert_eq!(output["modes"][0]["channels"][1], "strobe");
}

#[test]
fn gdtf_is_a_zip_with_description() {
    let output = export_gdtf(&fixture()).unwrap();
    assert!(output.description_xml.contains("DataVersion=\"1.2\""));
    let mut archive = zip::ZipArchive::new(Cursor::new(output.bytes)).unwrap();
    let mut xml = String::new();
    archive
        .by_name("description.xml")
        .unwrap()
        .read_to_string(&mut xml)
        .unwrap();
    assert!(xml.contains("<DMXMode Name=\"Full control\""));
    assert!(xml.contains("Attribute Name=\"Dimmer\""));
    assert!(xml.contains("Attribute Name=\"Shutter1Strobe\""));
    assert!(xml.contains("Feature=\"Beam.Beam\""));
}

#[test]
fn catches_overlapping_assignments() {
    let mut fixture = fixture();
    fixture.modes[0].channels[1].offset = 1;
    assert!(
        validate_fixture(&fixture)
            .iter()
            .any(|issue| issue.code == "assignment.overlap")
    );
}
