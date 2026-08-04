use std::{env, fs};

fn main() {
    let path = env::args().nth(1).expect("pass a .dmxtract.json file");
    let input = fs::read_to_string(path).expect("fixture project should be readable");
    println!(
        "{}",
        dmxtract_core::export_ofl_json(&input).expect("fixture should export")
    );
}
