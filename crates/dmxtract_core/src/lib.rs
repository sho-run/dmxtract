//! Canonical fixture model, validation, and format exporters for DMXtract.

mod export_gdtf;
mod export_ofl;
mod model;
mod validate;

pub use export_gdtf::{GdtfExport, export_gdtf};
pub use export_ofl::export_ofl;
pub use model::*;
pub use validate::{ValidationIssue, ValidationLevel, validate_fixture};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("fixture JSON is invalid: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("fixture contains blocking validation errors")]
    Validation,
    #[error("could not build archive: {0}")]
    Archive(#[from] zip::result::ZipError),
    #[error("could not write archive: {0}")]
    Io(#[from] std::io::Error),
}

pub fn fixture_schema_json() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&schemars::schema_for!(FixtureProject))
}

pub fn validate_fixture_json(json: &str) -> Result<String, CoreError> {
    let fixture: FixtureProject = serde_json::from_str(json)?;
    Ok(serde_json::to_string_pretty(&validate_fixture(&fixture))?)
}

pub fn export_ofl_json(json: &str) -> Result<String, CoreError> {
    let fixture: FixtureProject = serde_json::from_str(json)?;
    reject_blocking_issues(&fixture)?;
    Ok(serde_json::to_string_pretty(&export_ofl(&fixture))?)
}

pub fn export_gdtf_bytes(json: &str) -> Result<Vec<u8>, CoreError> {
    let fixture: FixtureProject = serde_json::from_str(json)?;
    reject_blocking_issues(&fixture)?;
    Ok(export_gdtf(&fixture)?.bytes)
}

fn reject_blocking_issues(fixture: &FixtureProject) -> Result<(), CoreError> {
    if validate_fixture(fixture)
        .iter()
        .any(|issue| issue.level == ValidationLevel::Error)
    {
        return Err(CoreError::Validation);
    }
    Ok(())
}

#[cfg(target_arch = "wasm32")]
mod wasm {
    use super::*;
    use wasm_bindgen::prelude::*;

    #[wasm_bindgen(js_name = fixtureSchema)]
    pub fn fixture_schema() -> Result<String, JsValue> {
        fixture_schema_json().map_err(|e| JsValue::from_str(&e.to_string()))
    }

    #[wasm_bindgen(js_name = validateFixture)]
    pub fn validate(json: &str) -> Result<String, JsValue> {
        validate_fixture_json(json).map_err(|e| JsValue::from_str(&e.to_string()))
    }

    #[wasm_bindgen(js_name = exportOfl)]
    pub fn ofl(json: &str) -> Result<String, JsValue> {
        export_ofl_json(json).map_err(|e| JsValue::from_str(&e.to_string()))
    }

    #[wasm_bindgen(js_name = exportGdtf)]
    pub fn gdtf(json: &str) -> Result<js_sys::Uint8Array, JsValue> {
        let bytes = export_gdtf_bytes(json).map_err(|e| JsValue::from_str(&e.to_string()))?;
        Ok(js_sys::Uint8Array::from(bytes.as_slice()))
    }
}
