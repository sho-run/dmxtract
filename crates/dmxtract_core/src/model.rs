use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub const FIXTURE_SCHEMA_ID: &str = "https://dmxtract.sho.run/schemas/fixture-v1.json";

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct FixtureProject {
    #[serde(default = "default_schema")]
    pub schema: String,
    #[serde(default = "default_schema_version")]
    pub schema_version: u8,
    pub id: String,
    pub identity: Identity,
    #[serde(default)]
    pub physical: Physical,
    #[serde(default)]
    pub provenance: Provenance,
    #[serde(default)]
    pub channels: Vec<Channel>,
    #[serde(default)]
    pub modes: Vec<Mode>,
    #[serde(default)]
    pub wheels: Vec<Wheel>,
    pub matrix: Option<Matrix>,
    #[serde(default)]
    pub geometry: Geometry,
}

fn default_schema() -> String {
    FIXTURE_SCHEMA_ID.to_owned()
}
fn default_schema_version() -> u8 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Identity {
    pub manufacturer: String,
    pub model: String,
    #[serde(default)]
    pub short_name: String,
    #[serde(default)]
    pub categories: Vec<String>,
    #[serde(default)]
    pub confidence: Confidence,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Physical {
    pub width_mm: Option<f64>,
    pub height_mm: Option<f64>,
    pub depth_mm: Option<f64>,
    pub weight_kg: Option<f64>,
    pub power_w: Option<f64>,
    pub lens_min_degrees: Option<f64>,
    pub lens_max_degrees: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Provenance {
    #[serde(default = "default_source_type")]
    pub source_type: String,
    #[serde(default)]
    pub source_name: String,
    #[serde(default)]
    pub identity_from_manual: bool,
    #[serde(default)]
    pub imported_at: String,
    #[serde(default)]
    pub notes: Vec<String>,
}

fn default_source_type() -> String {
    "manual".to_owned()
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Channel {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub kind: ChannelKind,
    #[serde(default)]
    pub gdtf_attribute: Option<String>,
    #[serde(default)]
    pub gdtf_feature: Option<String>,
    pub color: Option<ColorComponent>,
    pub fine_of: Option<String>,
    pub wheel_id: Option<String>,
    #[serde(default)]
    pub ranges: Vec<CapabilityRange>,
    #[serde(default)]
    pub confidence: Confidence,
    pub source: Option<SourceRegion>,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ChannelKind {
    Intensity,
    ColorIntensity,
    Pan,
    Tilt,
    Shutter,
    Strobe,
    ColorWheel,
    GoboWheel,
    GoboRotation,
    Focus,
    Zoom,
    Prism,
    Frost,
    Speed,
    Effect,
    Maintenance,
    #[default]
    Generic,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "UPPERCASE")]
pub enum ColorComponent {
    Red,
    Green,
    Blue,
    White,
    Amber,
    Uv,
    Cyan,
    Magenta,
    Yellow,
    Lime,
    Indigo,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityRange {
    pub start: u8,
    pub end: u8,
    pub name: String,
    pub capability: Option<ChannelKind>,
    pub wheel_slot: Option<u16>,
    #[serde(default)]
    pub safety: SafetyClass,
    #[serde(default)]
    pub confidence: Confidence,
    pub source: Option<SourceRegion>,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum SafetyClass {
    #[default]
    Normal,
    Strobe,
    Lamp,
    Reset,
    Maintenance,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Mode {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub short_name: String,
    #[serde(default = "default_breaks")]
    pub breaks: u16,
    #[serde(default)]
    pub channels: Vec<ChannelAssignment>,
    #[serde(default)]
    pub confidence: Confidence,
}

fn default_breaks() -> u16 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ChannelAssignment {
    pub channel_id: String,
    pub offset: u16,
    #[serde(default = "default_break")]
    pub dmx_break: u16,
}

fn default_break() -> u16 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Wheel {
    pub id: String,
    pub name: String,
    pub kind: WheelKind,
    #[serde(default)]
    pub slots: Vec<WheelSlot>,
    #[serde(default)]
    pub confidence: Confidence,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WheelKind {
    Color,
    Gobo,
    Animation,
    Prism,
    Effects,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WheelSlot {
    pub number: u16,
    pub name: String,
    pub color: Option<String>,
    pub media_file: Option<String>,
    #[serde(default)]
    pub confidence: Confidence,
    pub source: Option<SourceRegion>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Matrix {
    pub x: u16,
    pub y: u16,
    #[serde(default = "one")]
    pub z: u16,
    #[serde(default)]
    pub pixels: Vec<Pixel>,
    #[serde(default)]
    pub groups: Vec<PixelGroup>,
    #[serde(default)]
    pub template_channels: Vec<String>,
}

fn one() -> u16 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Pixel {
    pub id: String,
    pub x: u16,
    pub y: u16,
    #[serde(default)]
    pub z: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PixelGroup {
    pub name: String,
    #[serde(default)]
    pub pixel_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Geometry {
    #[serde(default = "default_body")]
    pub body: bool,
    #[serde(default)]
    pub yoke: bool,
    #[serde(default)]
    pub head: bool,
    #[serde(default = "default_beam")]
    pub beam: bool,
    #[serde(default)]
    pub pixel_emitters: bool,
}

impl Default for Geometry {
    fn default() -> Self {
        Self {
            body: true,
            yoke: false,
            head: false,
            beam: true,
            pixel_emitters: false,
        }
    }
}
fn default_body() -> bool {
    true
}
fn default_beam() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Confidence {
    #[serde(default = "one_f32")]
    pub score: f32,
    #[serde(default)]
    pub reason: String,
}
fn one_f32() -> f32 {
    1.0
}

impl Default for Confidence {
    fn default() -> Self {
        Self {
            score: 1.0,
            reason: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct SourceRegion {
    pub page: u32,
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    #[serde(default)]
    pub text: String,
}
