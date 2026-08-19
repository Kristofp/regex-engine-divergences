// Rust reference runner — uses the `regex` crate (same as Tier 1 Rust flavor)
// Reads JSON from stdin, outputs JSON to stdout.
// Compile: rustc --edition 2021 -o run_rust run_rust.rs -L ... (or use via orchestrator)
//
// Since this runner needs the `regex` crate, we build it as a Cargo example
// in src-tauri instead. The orchestrator calls:
//   cargo run --example corpus_runner_rust --manifest-path src-tauri/Cargo.toml

// This file is a placeholder — the actual runner is at:
//   src-tauri/examples/corpus_runner_rust.rs
