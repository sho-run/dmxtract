fn main() {
    println!(
        "{}",
        dmxtract_core::fixture_schema_json().expect("fixture schema should serialize")
    );
}
