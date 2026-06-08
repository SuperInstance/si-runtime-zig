# INTEGRATION.md — si-runtime-zig

Cross-language integration guide for the **SuperInstance Zig runtime** (`si-runtime-zig`).
This document shows the same conservation budget operation in all 7 supported languages,
how this library connects to the broader SuperInstance ecosystem, and FFI binding patterns.

---

## Table of Contents

1. [Same Operation in 7 Languages](#1-same-operation-in-7-languages)
2. [Cross-Repo Integration](#2-cross-repo-integration)
3. [FFI Bindings](#3-ffi-bindings)

---

## 1. Same Operation in 7 Languages

The canonical operation: **create a conservation budget of C=1000, allocate gamma=600 and eta=400, verify the invariant γ+η=C, then transfer 50 from gamma to eta.**

### Zig (si-runtime-zig — this repo)

```zig
const std = @import("std");
const conservation = @import("conservation.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Create budget with total C = 1000
    var budget = conservation.ConservationBudget.init(1000.0);

    // Allocate gamma (productive) and eta (waste)
    try budget.allocate(600.0, 400.0);

    // Audit: verify γ + η == C
    const report = try budget.audit();
    try stdout.print("gamma={d:.1} eta={d:.1} total={d:.1}\n",
        .{ report.gamma, report.eta, report.total });
    try stdout.print("utilization={d:.2}%\n", .{report.utilization * 100.0});

    // Transfer 50 from gamma to eta (from_gamma=true)
    try budget.transfer(true, 50.0);

    // Re-audit
    const after = try budget.audit();
    try stdout.print("After transfer: gamma={d:.1} eta={d:.1} total={d:.1}\n",
        .{ after.gamma, after.eta, after.total });
}
```

**Zig conservation module internals:**

```zig
// src/conservation.zig
pub const ConservationBudget = struct {
    gamma: f64,
    eta: f64,
    total: f64,

    pub fn init(total: f64) Self {
        return .{ .gamma = total / 2.0, .eta = total / 2.0, .total = total };
    }

    pub fn allocate(self: *Self, gamma: f64, eta: f64) ConservationError!void {
        if (gamma < 0 or eta < 0) return error.ConservationViolation;
        if (gamma + eta > self.total) return error.ConservationViolation;
        self.gamma = gamma;
        self.eta = eta;
    }

    pub fn transfer(self: *Self, from_gamma: bool, amount: f64) ConservationError!void {
        if (amount < 0) return error.ConservationViolation;
        if (from_gamma) {
            if (self.gamma < amount) return error.ConservationViolation;
            self.gamma -= amount;
            self.eta += amount;
        } else {
            if (self.eta < amount) return error.ConservationViolation;
            self.eta -= amount;
            self.gamma += amount;
        }
        // Invariant check
        if (!std.math.approxEqAbs(f64, self.gamma + self.eta, self.total, 1e-10))
            return error.ConservationViolation;
    }

    pub fn audit(self: *const Self) ConservationError!AuditReport {
        if (!std.math.approxEqAbs(f64, self.gamma + self.eta, self.total, 1e-10))
            return error.ConservationViolation;
        return .{
            .gamma = self.gamma,
            .eta = self.eta,
            .total = self.total,
            .utilization = ...,
        };
    }
};
```

### Rust (conservation-law-rs — reference implementation)

```rust
use conservation_law::ConservationBudget;

fn main() {
    let mut budget = ConservationBudget::new(1000.0);
    budget.allocate(600.0, 400.0).expect("allocation failed");

    let audit = budget.audit();
    assert!((audit.gamma + audit.eta - audit.total).abs() < 1e-10);
    println!("gamma={} eta={} total={}", audit.gamma, audit.eta, audit.total);

    budget.transfer("gamma", "eta", 50.0).expect("transfer failed");
    let audit = budget.audit();
    println!("After transfer: gamma={} eta={}", audit.gamma, audit.eta);
}
```

### C (si-core-c)

```c
#include "si_core.h"
#include <stdio.h>
#include <assert.h>

int main(void) {
    si_init();
    SiBudget *budget = budget_create(1000.0);
    budget_allocate(budget, 600.0, 400.0);

    BudgetReport rpt = budget_audit(budget);
    assert(rpt.violation == 0);
    printf("gamma=%.1f eta=%.1f total=%.1f\n", rpt.gamma, rpt.eta, rpt.total_budget);

    budget_transfer(budget, 0, 1, 50.0);
    rpt = budget_audit(budget);
    printf("After transfer: gamma=%.1f eta=%.1f\n", rpt.gamma, rpt.eta);

    budget_free(budget);
    si_shutdown();
    return 0;
}
```

### Python (si-runtime-python)

```python
from si_runtime import Budget, validate_budget

budget = Budget(total=1000.0, gamma=600.0, eta=400.0)
assert validate_budget(budget)
print(f"gamma={budget.gamma} eta={budget.eta} total={budget.total}")
```

### TypeScript (si-runtime-js)

```typescript
import { ConservationBudget } from 'si-runtime-js';

const budget = new ConservationBudget(1000);
budget.allocate(600, 400);
const report = budget.audit();
console.log(`gamma=${report.gamma} eta=${report.eta} total=${report.C}`);
budget.transfer('gamma', 'eta', 50);
```

### Go (si-runtime-go)

```go
package main

import siruntime "github.com/SuperInstance/si-runtime-go"

func main() {
    budget := siruntime.NewBudget(1000)
    budget.Allocate(600, 400)
    fmt.Printf("gamma=%.1f eta=%.1f total=%.1f\n",
        budget.Gamma, budget.Eta, budget.Total)
    budget.Transfer(50)
}
```

### WASM (si-runtime-wasm — from JavaScript)

```javascript
import init, { Budget } from 'si-runtime-wasm';

async function run() {
    await init();
    const budget = new Budget(1000);
    budget.allocate(300);
    budget.transfer_gamma_to_eta(50);
    console.log(`Audit: ${budget.audit()}`);
}
```

---

## 2. Cross-Repo Integration

### conservation-law-rs (Mathematical Foundation)

The Zig `ConservationBudget` struct mirrors the Rust `ConservationBudget` with identical
field layout (`gamma: f64, eta: f64, total: f64`). The `allocate()` and `transfer()`
methods enforce the same conservation law: γ+η=C. Zig's compile-time safety provides
additional guarantees at zero runtime cost.

**Connection points:**
- `ConservationBudget.init(total)` ↔ `ConservationBudget::new(C)`
- `ConservationBudget.allocate(γ, η)` ↔ `ConservationBudget::allocate(γ, η)`
- `ConservationBudget.transfer(from_gamma, amount)` ↔ `ConservationBudget::transfer()`
- `ConservationBudget.audit()` → `AuditReport` ↔ `ConservationBudget::audit()`

### spectral-fleet-rs (Fleet Ranking)

The Zig `spectral` module provides `powerIteration()`, `rank()`, `topK()`, and
`conditionNumber()` functions using the same deflation-based approach as
`spectral-fleet-rs`. The matrix format (slice of slices) is compatible with C ABI
representations.

**Connection points:**
- `spectral.rank(allocator, matrix, iterations)` ↔ Rust `rank()`
- `spectral.topK(allocator, matrix, k, iterations)` ↔ Rust `top_k()`
- `spectral.conditionNumber(allocator, matrix, iterations)` ↔ Rust `condition_number()`

### si-cli (CLI Discovery)

`si-cli` discovers Zig-based agents by compiling them to shared libraries and loading via
the C ABI. Zig's seamless C interop (`@cImport`) makes this trivial. The CLI calls
`ConservationBudget` and `Agent` functions directly.

**Connection points:**
- `Agent.init() / Agent.deinit()` → CLI agent lifecycle
- `Agent.decide(task_features)` → CLI task dispatch
- `Agent.transition(new_state)` → CLI state management
- `CapabilityManifest` → CLI capability discovery

### si-fleet-api (REST API Layer)

Zig agents expose their state through the C ABI, which `si-fleet-api` calls via its
Rust FFI layer. Budget audit data and spectral rankings flow from Zig → C ABI → REST.

**Connection points:**
- `ConservationBudget.audit()` → `GET /agents/:id/budget`
- `spectral.rank()` → `POST /fleet/rank`
- `Agent` state → `GET /agents/:id`

### Supabase Fleet Registry (Data Backend)

Zig agents don't connect to Supabase directly. Instead, the fleet API serializes Zig
agent state (obtained via C ABI) to JSON and persists it to Supabase.

**Connection points:**
- `AuditReport` fields → `agent_budgets` Supabase table
- `AgentState` enum → `agent_state` column
- `CapabilityManifest` → `capabilities` table

### sunset-ecosystem (Fleet Coordination)

`sunset-ecosystem` coordinates multi-fleet operations. Zig agents participate via the
C ABI, exposing budget transfers, state transitions, and spectral rankings for
fleet-wide coordination.

**Connection points:**
- `ConservationBudget.transfer()` for cross-agent budget movement
- `Agent.transition()` / `Agent.learn()` for fleet coordination
- `Cell.compose()` for computation pipeline construction
- `spectral.rank()` for fleet-level agent ranking

---

## 3. FFI Bindings

### Calling si-runtime-zig from C

Zig compiles to C-compatible object files. Export functions with `export`:

```zig
// export.zig
const conservation = @import("conservation.zig");

export fn zig_budget_create(total: f64) ?*conservation.ConservationBudget {
    const ptr = std.heap.c_allocator.create(conservation.ConservationBudget) catch return null;
    ptr.* = conservation.ConservationBudget.init(total);
    return ptr;
}

export fn zig_budget_allocate(b: *conservation.ConservationBudget, gamma: f64, eta: f64) c_int {
    b.allocate(gamma, eta) catch return -1;
    return 0;
}

export fn zig_budget_free(b: *conservation.ConservationBudget) void {
    std.heap.c_allocator.destroy(b);
}
```

```c
// caller.c
extern void* zig_budget_create(double total);
extern int   zig_budget_allocate(void *budget, double gamma, double eta);
extern void  zig_budget_free(void *budget);

int main(void) {
    void *budget = zig_budget_create(1000.0);
    zig_budget_allocate(budget, 600.0, 400.0);
    zig_budget_free(budget);
    return 0;
}
```

### Calling si-runtime-zig from Rust (via C ABI)

```rust
use std::os::raw::c_double;

extern "C" {
    fn zig_budget_create(total: c_double) -> *mut std::ffi::c_void;
    fn zig_budget_allocate(b: *mut std::ffi::c_void, gamma: c_double, eta: c_double) -> i32;
    fn zig_budget_free(b: *mut std::ffi::c_void);
}

fn main() {
    unsafe {
        let budget = zig_budget_create(1000.0);
        let err = zig_budget_allocate(budget, 600.0, 400.0);
        assert_eq!(err, 0);
        zig_budget_free(budget);
    }
}
```

### Calling si-runtime-zig from Python (via ctypes)

```python
import ctypes

lib = ctypes.CDLL("./libsi_runtime_zig.so")

lib.zig_budget_create.restype = ctypes.c_void_p
lib.zig_budget_create.argtypes = [ctypes.c_double]

lib.zig_budget_allocate.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_double]
lib.zig_budget_allocate.restype = ctypes.c_int

budget = lib.zig_budget_create(1000.0)
err = lib.zig_budget_allocate(budget, 600.0, 400.0)
assert err == 0
print(f"Zig budget allocated, err={err}")

lib.zig_budget_free(budget)
```

### Calling si-runtime-zig from Go (via cgo)

```go
package main

/*
#cgo LDFLAGS: -lsi_runtime_zig
extern void* zig_budget_create(double total);
extern int   zig_budget_allocate(void* budget, double gamma, double eta);
extern void  zig_budget_free(void* budget);
*/
import "C"
import "fmt"

func main() {
    budget := C.zig_budget_create(C.double(1000.0))
    err := C.zig_budget_allocate(budget, C.double(600.0), C.double(400.0))
    fmt.Printf("Zig allocate result: %d\n", int(err))
    C.zig_budget_free(budget)
}
```

### Calling C from Zig (via @cImport)

```zig
const c_si = @cImport(@cInclude("si_core.h"));

pub fn call_c_runtime() !void {
    c_si.si_init();
    const budget = c_si.budget_create(1000.0) orelse return error.CreationFailed;
    defer c_si.budget_free(budget);

    const err = c_si.budget_allocate(budget, 600.0, 400.0);
    if (err != 0) return error.AllocationFailed;
}
```

### Calling Rust from Zig (via C ABI)

```zig
// Rust exposes: extern "C" fn conservation_budget_new(C: f64) -> *mut opaque
const rust = @cImport(@cInclude("conservation_law.h"));

pub fn call_rust_budget() !void {
    const budget = rust.conservation_budget_new(1000.0) orelse return error.CreationFailed;
    defer rust.conservation_budget_free(budget);
    const err = rust.conservation_budget_allocate(budget, 600.0, 400.0);
    if (err != 0) return error.AllocationFailed;
}
```

### Calling si-runtime-zig from TypeScript/Node.js (via ffi-napi)

```typescript
import ffi from 'ffi-napi';

const lib = ffi.Library('./libsi_runtime_zig', {
    'zig_budget_create':   ['pointer', ['double']],
    'zig_budget_allocate': ['int',     ['pointer', 'double', 'double']],
    'zig_budget_free':     ['void',    ['pointer']],
});

const budget = lib.zig_budget_create(1000);
const err = lib.zig_budget_allocate(budget, 600, 400);
console.log('Zig allocate result:', err);
lib.zig_budget_free(budget);
```

---

## Integration Test Matrix

| From → To | C | Rust | Python | TypeScript | Zig | Go | WASM |
|---|---|---|---|---|---|---|---|
| **Zig** | `@cImport` | C ABI | ctypes | ffi-napi | ✅ native | cgo | N/A |
| **C** | ✅ native | cdylib | ctypes | ffi-napi | link | cgo | emscripten |
| **Rust** | extern "C" | ✅ native | PyO3 | wasm-bindgen | C ABI | C ABI | wasm-bindgen |
| **Python** | ctypes | PyO3 | ✅ native | pythonia | ctypes | cgo | N/A |
| **TypeScript** | ffi-napi | wasm-bindgen | pythonia | ✅ native | ffi-napi | HTTP bridge | wasm API |
| **Go** | cgo | C ABI | C API | HTTP bridge | cgo | ✅ native | N/A |
| **WASM** | emscripten | wasm-bindgen | N/A | JS import | N/A | N/A | ✅ native |

---

## Zig Module API Summary

| Module | Type | Description |
|---|---|---|
| `conservation` | `ConservationBudget` | Budget with γ+η=C invariant |
| `conservation` | `AuditReport` | Audit result struct |
| `spectral` | `powerIteration()` | Full eigen-decomposition via deflation |
| `spectral` | `rank()` | Sorted indices by eigenvalue magnitude |
| `spectral` | `topK()` | Top-k ranked indices |
| `spectral` | `conditionNumber()` | Spectral condition number |
| `capability` | `CapabilityManifest` | Parsed TOML capability |
| `capability` | `parseCapabilityToml()` | Parse TOML string |
| `capability` | `suggestIntegrations()` | Find integration pairs |
| `cell` | `Cell` | Composable computation unit |
| `cell` | `compose()` | Cell composition |
| `agent` | `Agent` | State machine with budget and spectral ranking |
| `agent` | `AgentState` | Enum: idle, thinking, executing, learning, err |

---

*Generated for SuperInstance cross-language integration — si-runtime-zig v0.1.0*
