use crate::{FixtureProject, SafetyClass};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ValidationLevel {
    Error,
    Warning,
    Help,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ValidationIssue {
    pub level: ValidationLevel,
    pub code: String,
    pub path: String,
    pub message: String,
}

pub fn validate_fixture(fixture: &FixtureProject) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    if fixture.identity.manufacturer.trim().is_empty() {
        error(
            &mut issues,
            "identity.manufacturer",
            "manufacturer.required",
            "Add the name printed on the light or manual.",
        );
    }
    if fixture.identity.model.trim().is_empty() {
        error(
            &mut issues,
            "identity.model",
            "model.required",
            "Add the fixture model name.",
        );
    }
    if fixture.modes.is_empty() {
        error(
            &mut issues,
            "modes",
            "mode.required",
            "Add at least one mode from the light's DMX table.",
        );
    }

    let mut channel_ids = HashSet::new();
    for (index, channel) in fixture.channels.iter().enumerate() {
        if !channel_ids.insert(channel.id.as_str()) {
            error(
                &mut issues,
                &format!("channels[{index}].id"),
                "channel.duplicate",
                "Each control needs a unique identifier.",
            );
        }
        let mut ranges = channel.ranges.clone();
        ranges.sort_by_key(|range| range.start);
        for (range_index, range) in ranges.iter().enumerate() {
            if range.start > range.end {
                error(
                    &mut issues,
                    &format!("channels[{index}].ranges[{range_index}]"),
                    "range.reversed",
                    "The first DMX value must be no greater than the last value.",
                );
            }
            if range_index > 0 && range.start <= ranges[range_index - 1].end {
                error(
                    &mut issues,
                    &format!("channels[{index}].ranges[{range_index}]"),
                    "range.overlap",
                    "This value range overlaps the one before it.",
                );
            }
            if range.confidence.score < 0.6 {
                warning(
                    &mut issues,
                    &format!("channels[{index}].ranges[{range_index}]"),
                    "range.uncertain",
                    &format!("Check the values for {}.", range.name),
                );
            }
            if range.safety != SafetyClass::Normal && range.name.trim().is_empty() {
                warning(
                    &mut issues,
                    &format!("channels[{index}].ranges[{range_index}]"),
                    "safety.unnamed",
                    "Name this risky range so testers know what it does.",
                );
            }
        }
        if let Some(fine_of) = &channel.fine_of
            && !fixture.channels.iter().any(|coarse| &coarse.id == fine_of)
        {
            error(
                &mut issues,
                &format!("channels[{index}].fineOf"),
                "fine.missingCoarse",
                "The linked coarse control could not be found.",
            );
        }
    }

    for (mode_index, mode) in fixture.modes.iter().enumerate() {
        let mut positions: HashMap<(u16, u16), &str> = HashMap::new();
        for (assignment_index, assignment) in mode.channels.iter().enumerate() {
            let path = format!("modes[{mode_index}].channels[{assignment_index}]");
            if !channel_ids.contains(assignment.channel_id.as_str()) {
                error(
                    &mut issues,
                    &path,
                    "assignment.unknownChannel",
                    "This mode points to a control that no longer exists.",
                );
            }
            if assignment.offset == 0 || assignment.offset > 512 {
                error(
                    &mut issues,
                    &format!("{path}.offset"),
                    "assignment.offset",
                    "A channel number must be between 1 and 512.",
                );
            }
            if assignment.dmx_break == 0 || assignment.dmx_break > mode.breaks.max(1) {
                error(
                    &mut issues,
                    &format!("{path}.dmxBreak"),
                    "assignment.break",
                    "This universe is not included in the mode.",
                );
            }
            if let Some(existing) = positions.insert(
                (assignment.dmx_break, assignment.offset),
                &assignment.channel_id,
            ) {
                error(
                    &mut issues,
                    &path,
                    "assignment.overlap",
                    &format!("This shares channel {} with {existing}.", assignment.offset),
                );
            }
        }
    }

    if let Some(matrix) = &fixture.matrix {
        let expected = usize::from(matrix.x) * usize::from(matrix.y) * usize::from(matrix.z.max(1));
        if !matrix.pixels.is_empty() && matrix.pixels.len() != expected {
            warning(
                &mut issues,
                "matrix.pixels",
                "matrix.count",
                "The pixel count does not match the matrix dimensions.",
            );
        }
    }
    issues
}

fn push(
    issues: &mut Vec<ValidationIssue>,
    level: ValidationLevel,
    path: &str,
    code: &str,
    message: &str,
) {
    issues.push(ValidationIssue {
        level,
        code: code.to_owned(),
        path: path.to_owned(),
        message: message.to_owned(),
    });
}
fn error(issues: &mut Vec<ValidationIssue>, path: &str, code: &str, message: &str) {
    push(issues, ValidationLevel::Error, path, code, message);
}
fn warning(issues: &mut Vec<ValidationIssue>, path: &str, code: &str, message: &str) {
    push(issues, ValidationLevel::Warning, path, code, message);
}
