# MenteDB Flutter SDK Contract

This package contains the stable Dart facade and DTOs for a native Flutter
integration. It intentionally does not check in generated Flutter Rust Bridge
output. Generated bindings or a custom Dart FFI adapter should implement
`MenteDbNativeBridge` and return the DTOs exported by this package.

Recommended native shape:

1. Use Flutter Rust Bridge for Android, iOS, macOS, Windows, and Linux.
2. Keep one Rust `MenteDb` handle per user vault or app profile.
3. Expose graph projection through `MenteDb::graph_projection`.
4. Run background maintenance through `MenteDb::try_run_sleep_maintenance`.
5. Run LLM enrichment through `try_run_enrichment_with_lease` when the Rust
   crate is built with the `enrichment` feature.

This package does not target Flutter web.

The runnable example app under `example/` compares an OpenAI-compatible chat
completion with and without memory context, and includes a text memory bank that
can be edited at runtime.
