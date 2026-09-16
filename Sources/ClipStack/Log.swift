import os

/// Diagnostics for the paste path, which is the part that fails silently and
/// invisibly when a permission or a focus hand-off goes wrong.
///
/// Watch it live with:
///     log stream --predicate 'subsystem == "com.mickey.clipstack"'
/// or after the fact with:
///     log show --predicate 'subsystem == "com.mickey.clipstack"' --last 5m
///
/// Deliberately never logs clipboard contents — only state and key codes.
let pasteLog = Logger(subsystem: "com.mickey.clipstack", category: "paste")
