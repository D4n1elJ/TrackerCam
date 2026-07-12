// ============================================================================
// SIM RIG PRICE LIST — edit this file to update configurator pricing.
//
// Prices are in USD and were researched from supplier websites
// (trakracer.com, simucube.com, heusinkveld.com and US resellers) in
// July 2026. The configurator shows every total as a range of ±15%,
// so prices here only need to be roughly right. Update the `price`
// numbers (and `asOf`) whenever suppliers change theirs.
//
// To add a product: copy an existing line inside the right category.
// To remove one: delete its line. Nothing else needs to change.
// ============================================================================

export const PRICE_TOLERANCE = 0.15; // ±15% shown around every estimate

export const simPricing = {
  asOf: "July 2026",
  categories: [
    {
      id: "cockpit",
      name: "Cockpit / Chassis",
      blurb: "The aluminium-profile frame everything bolts to.",
      required: true,
      multi: false,
      options: [
        { id: "tr8pro", label: "Trak Racer TR8 Pro", supplier: "Trak Racer", price: 599, note: "Great entry point, tubular steel" },
        { id: "tr120", label: "Trak Racer TR120S V2 (with seat slider)", supplier: "Trak Racer", price: 719, note: "Aluminium profile, mid-range" },
        { id: "tr160", label: "Trak Racer TR160 V5 (with seat slider)", supplier: "Trak Racer", price: 879, note: "160mm profile, rock solid for direct drive" },
        { id: "tr160s", label: "Trak Racer TR160S V2", supplier: "Trak Racer", price: 1199, note: "Flagship enclosed-profile chassis" },
      ],
    },
    {
      id: "wheelbase",
      name: "Wheelbase (Direct Drive)",
      blurb: "The motor that generates force feedback — the heart of the rig.",
      required: true,
      multi: false,
      options: [
        { id: "sc2sport", label: "Simucube 2 Sport (17 Nm)", supplier: "Simucube", price: 1360, note: "Plenty for most drivers" },
        { id: "sc2pro", label: "Simucube 2 Pro (25 Nm)", supplier: "Simucube", price: 1550, note: "The pro-enthusiast sweet spot" },
        { id: "sc2ultimate", label: "Simucube 2 Ultimate (32 Nm)", supplier: "Simucube", price: 3300, note: "No-compromise flagship" },
      ],
    },
    {
      id: "wheel",
      name: "Steering Wheel",
      blurb: "Wireless or USB rim mounted to the wheelbase.",
      required: true,
      multi: false,
      options: [
        { id: "tahko", label: "Simucube Tahko GT-21", supplier: "Simucube", price: 860, note: "Wireless GT rim" },
        { id: "valo", label: "Simucube Valo GT-23", supplier: "Simucube", price: 1200, note: "Premium wireless GT rim" },
        { id: "csx3", label: "Cube Controls Formula CSX-3", supplier: "Cube Controls", price: 940, note: "Carbon formula rim" },
        { id: "ownwheel", label: "Use my own wheel", supplier: "—", price: 0, note: "Bring your existing rim" },
      ],
    },
    {
      id: "pedals",
      name: "Pedals",
      blurb: "Load-cell pedals — the biggest upgrade to lap times.",
      required: true,
      multi: false,
      options: [
        { id: "sprint2", label: "Heusinkveld Sprint (2-pedal)", supplier: "Heusinkveld", price: 730, note: "Throttle + load-cell brake" },
        { id: "sprint3", label: "Heusinkveld Sprint (3-pedal)", supplier: "Heusinkveld", price: 840, note: "Adds clutch" },
        { id: "ultimate2", label: "Heusinkveld Ultimate+ (2-pedal)", supplier: "Heusinkveld", price: 1240, note: "Pro-grade hydraulic damping" },
        { id: "ultimate3", label: "Heusinkveld Ultimate+ (3-pedal)", supplier: "Heusinkveld", price: 1620, note: "The full pro set" },
      ],
    },
    {
      id: "seat",
      name: "Seat",
      blurb: "Fixed-back buckets hold you in place under heavy braking.",
      required: true,
      multi: false,
      options: [
        { id: "trseat", label: "Trak Racer GT/Rally bucket seat", supplier: "Trak Racer", price: 349, note: "Solid all-rounder" },
        { id: "premiumseat", label: "Premium bucket seat (Sparco / Cobra)", supplier: "Sparco / Cobra", price: 650, note: "Real motorsport shell" },
        { id: "ownseat", label: "Use my own seat", supplier: "—", price: 0, note: "" },
      ],
    },
    {
      id: "display",
      name: "Display & Mounting",
      blurb: "Monitor(s) plus the stand or integrated mount.",
      required: true,
      multi: false,
      options: [
        { id: "nodisplay", label: "Use my own display", supplier: "—", price: 0, note: "" },
        { id: "single32", label: 'Single 32" QHD 165Hz + freestanding mount', supplier: "Various + Trak Racer", price: 530, note: "" },
        { id: "uw49", label: '49" super-ultrawide + freestanding mount', supplier: "Various + Trak Racer", price: 1100, note: "Immersive single-screen setup" },
        { id: "triple32", label: 'Triple 32" QHD 165Hz + integrated triple mount', supplier: "Various + Trak Racer", price: 1490, note: "The full FOV experience" },
      ],
    },
    {
      id: "addons",
      name: "Add-ons",
      blurb: "Optional extras — pick as many as you like.",
      required: false,
      multi: true,
      options: [
        { id: "shifter", label: "Heusinkveld Sim Shifter Sequential", supplier: "Heusinkveld", price: 520, note: "" },
        { id: "handbrake", label: "Heusinkveld Sim Handbrake", supplier: "Heusinkveld", price: 260, note: "Drift & rally essential" },
        { id: "buttonbox", label: "Button box", supplier: "Various", price: 250, note: "" },
        { id: "keyboardtray", label: "Keyboard & mouse tray", supplier: "Trak Racer", price: 89, note: "" },
        { id: "casters", label: "Caster wheel kit", supplier: "Trak Racer", price: 79, note: "Roll the rig out of the way" },
        { id: "shakers", label: "Bass shaker kit (2x transducer + amp)", supplier: "Dayton Audio", price: 220, note: "Feel kerbs, gearshifts and lock-ups" },
      ],
    },
    {
      id: "pc",
      name: "Sim PC",
      blurb: "A machine that can actually drive triple screens.",
      required: false,
      multi: false,
      options: [
        { id: "nopc", label: "Use my own PC", supplier: "—", price: 0, note: "" },
        { id: "midpc", label: "Mid-range sim PC (RTX 5070-class)", supplier: "Custom build", price: 1600, note: "High FPS on single/ultrawide" },
        { id: "highpc", label: "High-end sim PC (RTX 5080-class)", supplier: "Custom build", price: 2800, note: "Triples & VR without compromise" },
      ],
    },
  ],
} as const;

export type SimCategory = (typeof simPricing.categories)[number];
export type SimOption = SimCategory["options"][number];
