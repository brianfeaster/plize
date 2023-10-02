use std::{process::Command, str::from_utf8};

fn main() {
    Command::new("bash")
        .arg("-c")
        .arg(r#"printf $'\e[1mComing Soon...Plize - A bash command line scheduler implemented in Rust 2021.\e[0m' >&2"#)
        .output()
        .map_err(|e| println!("EXCEPTION::command::{}", e))
        .and_then(|output|
            from_utf8(&output.stderr)
            .map_err(|e| println!("EXCEPTION::from_utf8::{}", e))
            .map(|s| println!("{}", s)))
        .ok();
}
