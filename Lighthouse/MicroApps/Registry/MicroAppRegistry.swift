// Registry used by launcher autocomplete and slash micro app matching.
let knownMicroApps: [(key: String, desc: String, symbol: String)] = [
    ("settings", lh("microapp.settings.desc"),  "gearshape"),
    ("storage", lh("microapp.storage.desc"),    "internaldrive"),
    ("cpu", lh("microapp.cpu.desc"),            "cpu"),
    ("memory", lh("microapp.memory.desc"),      "memorychip"),
    ("uptime", lh("microapp.uptime.desc"),      "clock"),
    ("stopwatch", lh("microapp.stopwatch.desc"), "timer"),
    ("timer", lh("microapp.timer.desc"),        "hourglass"),
]

// Per-micro-app placeholder shown when argument input mode is active.
let microAppArgsPlaceholders: [String: String] = [
    "timer": lh("microapp.timer.placeholder"),
]

// Micro apps that require additional user input before execution.
let microAppsAcceptingArgs: Set<String> = [
    "timer",
]
