# si-runtime-zig

General-purpose Zig runtime for constraint-aware AI: conservation budgets, spectral ranking, capability discovery, and cell composition.

## Why Zig?

- **Comptime** — Generate state machines, transition tables, and serializers at compile time. Zero runtime cost for things Zig can figure out during compilation.
- **No hidden allocations** — Every allocation is explicit via Zig's allocator pattern. You always know where memory comes from and when it's freed.
- **Cross-compile** — Build for any target from any host. `zig build -Dtarget=aarch64-linux-gnu` just works.
- **No dependencies** — Pure stdlib. No build.gradle, no cargo lockfiles, no npm_modules. One compiler, one repo.
- **Small binaries** — Static linking with no runtime. Perfect for embedding in constrained environments.

## Build

```bash
# Build the library
zig build

# Run all tests
zig build test

# Run the demo
zig build run

# Check compilation
zig build check
```

## API Overview

### Conservation Budget

Enforces the invariant `γ + η = total` across all operations. Any violation returns `error.ConservationViolation`.

```zig
var budget = ConservationBudget.init(100.0);
try budget.allocate(40.0, 60.0);     // γ=40, η=60
try budget.transfer(true, 10.0);      // move 10 from γ to η
const report = try budget.audit();    // verify invariant
```

### Spectral Ranking

Power iteration-based eigenvalue decomposition. Allocator-owned, no hidden allocations.

```zig
const matrix = &[_][]const f64{
    &[_]f64{ 4.0, 1.0 },
    &[_]f64{ 1.0, 3.0 },
};
const ranked = try spectral.rank(allocator, matrix, 200);
const top = try spectral.topK(allocator, matrix, 2, 200);
const cn = try spectral.conditionNumber(allocator, matrix, 200);
```

### Capability Discovery

Parse TOML manifests, scan directories, and suggest integrations between capabilities.

```zig
const manifest = try capability.parseCapabilityToml(allocator, toml_content);
const manifests = try capability.scanDirectory(allocator, "./caps/");
const suggestions = try capability.suggestIntegrations(allocator, manifests);
```

### Cell Composition

Cells are budget-tracked execution units that can be piped together.

```zig
var cell = Cell.init(allocator, "my_cell", 100.0, myHandler);
try cell.addDep("upstream");
const result = try cell.execute("input data");

// Compose: pipe a → b
var composed = try cell.compose(allocator, &a, &b);
```

### Agent

State machine with valid transitions: `idle → thinking → executing → learning → idle`. Any state can transition to `err`, and `err` can recover to `idle`.

```zig
var agent = try Agent.init(allocator, 200.0, &capabilities);
try agent.transition(.thinking);
const action = try agent.decide(&task_features);
try agent.transition(.executing);
agent.learn(reward, cost);
```

## Project Structure

```
├── build.zig              # Build configuration
├── src/
│   ├── root.zig           # Main module, re-exports all types
│   ├── conservation.zig   # Conservation budget enforcement
│   ├── spectral.zig       # Eigenvalue decomposition and ranking
│   ├── capability.zig     # Capability manifest parsing and discovery
│   ├── cell.zig           # Budget-tracked cell execution
│   ├── agent.zig          # Stateful agent with lifecycle management
│   └── main.zig           # CLI demo
├── tests/
│   ├── conservation_test.zig
│   ├── spectral_test.zig
│   ├── capability_test.zig
│   ├── cell_test.zig
│   └── agent_test.zig
└── README.md
```

## License

MIT
