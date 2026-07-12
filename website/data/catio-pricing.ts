// ============================================================================
// CATIO PRICE MODEL — !! ALL RATES BELOW ARE PLACEHOLDERS !!
//
// Replace every number marked PLACEHOLDER with your real rates (materials +
// labor) to get accurate real-time estimates. Units are US dollars and feet.
// The configurator shows every total as a range of ±15%.
//
// How the estimate is computed:
//   wall area  = perimeter of enclosed sides × height
//   roof area  = length × width (only when a roof is selected)
//   total      = baseFee
//              + wall area × mesh rate
//              + roof area × roof rate
//              + bends × perBend
//              + doors × perDoor
// ============================================================================

export const catioPricing = {
  asOf: "July 2026",

  // Flat fee per project: site visit, design, fasteners, travel. PLACEHOLDER
  baseFee: 350,

  // Framed wall panels incl. mesh, per square foot of wall. PLACEHOLDER
  meshWallRates: {
    standard: { label: "Standard galvanized mesh", perSqFt: 6.5 },
    heavyDuty: { label: "Heavy-duty welded wire (dog-proof)", perSqFt: 9.0 },
  },

  // Roof options, per square foot of footprint. PLACEHOLDER
  roofRates: {
    none: { label: "No roof (walls only)", perSqFt: 0 },
    mesh: { label: "Mesh roof", perSqFt: 7.0 },
    polycarbonate: { label: "Polycarbonate roof (rain cover)", perSqFt: 14.0 },
  },

  // Each bend/corner beyond a straight run adds posts & framing. PLACEHOLDER
  perBend: 120,

  // Human-sized access door, framed and hinged. PLACEHOLDER
  perDoor: 180,

  // Reasonable input limits for the form (feet).
  limits: {
    maxLength: 100,
    maxWidth: 50,
    maxHeight: 12,
    maxBends: 12,
    maxDoors: 4,
  },
};
