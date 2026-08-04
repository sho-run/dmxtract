use std::{env, fs};

fn main() {
    let input_path = env::args().nth(1).expect("pass a .dmxtract.json file");
    let output_path = env::args().nth(2).expect("pass an output .gdtf path");
    let input = fs::read_to_string(input_path).expect("fixture project should be readable");
    let bytes = dmxtract_core::export_gdtf_bytes(&input).expect("fixture should export");
    fs::write(output_path, bytes).expect("GDTF output should be writable");
}
