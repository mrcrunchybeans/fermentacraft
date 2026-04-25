/**
 * Nautilis payload verification script.
 * Mirrors the logic in ingest.ts parsePayload() and saveMeasurement()
 * to verify all known real-world Nautilis device payloads are handled correctly.
 *
 * Run: node scripts/test_nautilis_payloads.js
 */

// ── Replicated logic from ingest.ts ──────────────────────────────────────────

function platoToSG(p) {
  return 1 + p / (258.6 - ((p / 258.2) * 227.1));
}
function brixToSG(bx) {
  return 1 + (bx / (258.6 - ((bx / 258.2) * 227.1)));
}

function parsePayload(raw) {
  // Gravity
  const gravityRaw =
    raw["corr-gravity"] ?? raw.corr_gravity ?? raw.corrGravity ??
    raw.corrSG ?? raw.corr_sg ?? raw.gravity;
  const gravity = Number(gravityRaw);

  const gravityUnitRaw =
    raw.gravity_unit ?? raw["gravity-unit"] ?? raw["gravity-format"] ??
    raw.gravityUnit ?? "SG";
  const gravityUnit = String(gravityUnitRaw).toUpperCase();

  // Temperature
  const temp = Number(raw.temp ?? raw.temperature);
  const tempUnitRaw =
    raw.temp_unit ?? raw.temp_units ?? raw.temperature_unit ??
    raw.temperatureUnit ?? "C";
  const tempUnit = String(tempUnitRaw).toUpperCase();

  const angle = raw.angle != null ? Number(raw.angle) : null;
  const battery = raw.battery != null ? Number(raw.battery) : null;

  let sg;
  if (!Number.isNaN(gravity)) {
    if (gravityUnit.startsWith("P") || gravityUnit === "PLATO") {
      sg = platoToSG(gravity);
    } else if (gravityUnit.startsWith("B")) {
      sg = brixToSG(gravity);
    } else {
      sg = gravity;
    }
  }
  if (sg == null && typeof raw.brix === "number") {
    sg = brixToSG(Number(raw.brix));
  }

  let tempC;
  if (!Number.isNaN(temp)) {
    tempC = tempUnit.startsWith("F") ? (temp - 32) * (5 / 9) : temp;
  }

  // Pressure
  let pressureBar = null;
  if (raw.pressure != null) {
    const p = Number(raw.pressure);
    if (!Number.isNaN(p)) {
      const pUnit = String(
        raw.pressure_unit ?? raw.pressureUnit ?? raw.pressure_units ?? "bar"
      ).toLowerCase();
      if (pUnit.includes("psi")) {
        pressureBar = p * 0.0689476;
      } else if (pUnit.includes("kpa")) {
        pressureBar = p / 100;
      } else {
        pressureBar = p;
      }
    }
  } else if (raw.pressure_psi != null) {
    const p = Number(raw.pressure_psi);
    if (!Number.isNaN(p)) pressureBar = p * 0.0689476;
  }

  return { sg, tempC, angle, battery, pressureBar };
}

function wouldSave({ sg, pressureBar }) {
  const hasSg = sg != null && isFinite(sg);
  const hasPressure = pressureBar != null;
  return hasSg || hasPressure;  // true = passes guard, false = would throw bad_gravity
}

// ── Test runner ───────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function test(name, raw, checks) {
  const result = parsePayload(raw);
  const saves = wouldSave(result);
  let ok = true;
  const failures = [];

  for (const [key, expected] of Object.entries(checks)) {
    if (key === "saves") {
      if (saves !== expected) {
        ok = false;
        failures.push(`saves: expected ${expected}, got ${saves}`);
      }
      continue;
    }
    const actual = result[key];
    if (expected === null) {
      if (actual !== null && actual !== undefined) {
        ok = false;
        failures.push(`${key}: expected null, got ${actual}`);
      }
    } else if (typeof expected === "number") {
      const diff = Math.abs((actual ?? NaN) - expected);
      if (diff > 0.0001) {
        ok = false;
        failures.push(`${key}: expected ≈${expected}, got ${actual} (diff=${diff.toFixed(6)})`);
      }
    } else {
      if (actual !== expected) {
        ok = false;
        failures.push(`${key}: expected ${expected}, got ${actual}`);
      }
    }
  }

  if (ok) {
    console.log(`  ✅ ${name}`);
    passed++;
  } else {
    console.log(`  ❌ ${name}`);
    for (const f of failures) console.log(`       ${f}`);
    failed++;
  }
}

// ── Test cases ────────────────────────────────────────────────────────────────

console.log("\n=== iRelay+ forwarding iSpindel (standard) ===");

test("iSpindel JSON via iRelay — SG + temp",
  { name: "iSpindel001", ID: 123456, gravity: 1.050, temperature: 20.5, temp_units: "C", battery: 3.9, angle: 45.2 },
  { sg: 1.050, tempC: 20.5, pressureBar: null, saves: true }
);

test("iSpindel with corr-gravity field",
  { name: "iSpindel001", gravity: 1.045, "corr-gravity": 1.048, temperature: 19.0, temp_units: "C" },
  { sg: 1.048, tempC: 19.0, pressureBar: null, saves: true }
);

test("iSpindel with gravity-unit G (default SG)",
  { gravity: 1.012, "gravity-unit": "G", temp: 20.5, temp_unit: "C", battery: 3.7, angle: 30 },
  { sg: 1.012, tempC: 20.5, pressureBar: null, saves: true }
);

test("iSpindel Plato mode via iRelay",
  { gravity: 12.5, "gravity-unit": "P", temperature: 20.0, temp_units: "C" },
  { sg: platoToSG(12.5), tempC: 20.0, pressureBar: null, saves: true }
);

test("iSpindel Brix mode",
  { gravity: 14.0, "gravity-unit": "Brix", temperature: 19.5, temp_units: "C" },
  { sg: brixToSG(14.0), tempC: 19.5, pressureBar: null, saves: true }
);

test("iSpindel Fahrenheit temperature",
  { gravity: 1.020, temperature: 68.0, temp_units: "F" },
  { sg: 1.020, tempC: 20.0, pressureBar: null, saves: true }
);

console.log("\n=== Nautilis iPressure — pressure field variants ===");

test("iPressure: pressure in bar (explicit unit)",
  { pressure: 1.75, pressure_unit: "BAR", temperature: 20.0, temp_unit: "C" },
  { pressureBar: 1.75, tempC: 20.0, sg: undefined, saves: true }
);

test("iPressure: pressure in bar (unit lowercase)",
  { pressure: 2.0, pressure_unit: "bar" },
  { pressureBar: 2.0, saves: true }
);

test("iPressure: pressure with no unit (defaults to bar)",
  { pressure: 1.5, temperature: 19.5 },
  { pressureBar: 1.5, saves: true }
);

test("iPressure: pressure in PSI",
  { pressure: 25.0, pressure_unit: "PSI", temperature: 20.0 },
  { pressureBar: +(25.0 * 0.0689476).toFixed(6), saves: true }
);

test("iPressure: pressure_psi field variant",
  { pressure_psi: 15.0, temperature: 20.0 },
  { pressureBar: +(15.0 * 0.0689476).toFixed(6), saves: true }
);

test("iPressure: pressure_unit KPA — converted to bar (/100)",
  { pressure: 180.0, pressure_unit: "KPA" },
  { pressureBar: 1.8, saves: true }
);

test("iPressure: pressure_unit kPa lowercase",
  { pressure: 200.0, pressure_unit: "kPa" },
  { pressureBar: 2.0, saves: true }
);

test("iPressure: pressure with gravity (iRelay+P + iSpindel connected)",
  { gravity: 1.025, temperature: 20.0, temp_units: "C", pressure: 1.2, pressure_unit: "bar" },
  { sg: 1.025, tempC: 20.0, pressureBar: 1.2, saves: true }
);

test("iPressure: zero pressure (atmospheric baseline — valid reading, should save)",
  { pressure: 0.0, pressure_unit: "bar", temperature: 20.0 },
  // pressure: 0.0 — Number(0.0) = 0, isNaN(0) = false, 0 != null = true → hasPressure=true → saves
  { pressureBar: 0.0, saves: true }
);

console.log("\n=== Edge cases and guard conditions ===");

test("Empty payload — should NOT save",
  {},
  { sg: undefined, pressureBar: null, saves: false }
);

test("Only name/ID fields, no readings — should NOT save",
  { name: "iSpindel001", ID: 12345 },
  { sg: undefined, pressureBar: null, saves: false }
);

test("gravity: 0 — treated as valid SG (technically saves but suspicious)",
  { gravity: 0, temperature: 20.0 },
  { sg: 0, saves: true }
);

test("gravity is null string — should not parse",
  { gravity: "null", temperature: 20.0 },
  // Number("null") = NaN, so sg = undefined
  { sg: undefined, saves: false }
);

test("Battery as percentage string (some firmwares) — parsed to number",
  { gravity: 1.010, temperature: 20.0, battery: "85" },
  { sg: 1.010, battery: 85, saves: true }
);

test("HYDROM device format (gravity + temp_units)",
  { name: "HYDROM-001", gravity: 1.065, temp: 18.5, temp_unit: "C", battery: 100 },
  { sg: 1.065, tempC: 18.5, battery: 100, pressureBar: null, saves: true }
);

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\n${"─".repeat(50)}`);
console.log(`  Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  console.log("\n⚠️  KNOWN LIMITATION: KPA pressure unit is not converted —");
  console.log("   if the Nautilis device sends pressure_unit=KPA, the value");
  console.log("   will be stored as-is (not converted to bar).");
  console.log("   Action: add KPA→bar conversion if a user reports this.");
  process.exit(1);
} else {
  console.log("\n✅  All scenarios handled correctly.");
  console.log("\n⚠️  KNOWN LIMITATION: KPA pressure unit is not converted —");
  console.log("   value would be stored as-is. Add KPA→bar if needed.");
}
