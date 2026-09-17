import os

/// Diagnostics for the paths that fail silently and invisibly — pasting, when a
/// permission or a focus hand-off goes wrong, and login-item registration, which
/// the system can refuse without telling anyone.
///
/// Watch it live with:
///     log stream --predicate 'subsystem == "com.mickey.clipstack"'
/// or after the fact with:
///     log show --predicate 'subsystem == "com.mickey.clipstack"' --last 5m
///
/// Deliberately never logs clipboard contents — only state and key codes.
let pasteLog = Logger(subsystem: "com.mickey.clipstack", category: "paste")
let loginLog = Logger(subsystem: "com.mickey.clipstack", category: "login")
