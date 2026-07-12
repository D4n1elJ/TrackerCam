"use client";

import { useMemo, useState } from "react";
import { catioPricing } from "@/data/catio-pricing";
import { siteConfig } from "@/data/site-config";

const usd = (n: number) =>
  n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  });

const TOLERANCE = 0.15;

type MeshKey = keyof typeof catioPricing.meshWallRates;
type RoofKey = keyof typeof catioPricing.roofRates;

export default function CatioConfigurator() {
  const { limits } = catioPricing;
  const [length, setLength] = useState(10);
  const [width, setWidth] = useState(6);
  const [height, setHeight] = useState(8);
  const [bends, setBends] = useState(0);
  const [doors, setDoors] = useState(1);
  const [attached, setAttached] = useState(true);
  const [mesh, setMesh] = useState<MeshKey>("standard");
  const [roof, setRoof] = useState<RoofKey>("mesh");

  const est = useMemo(() => {
    // Attached catios use the house as one long wall, so that side needs no panel.
    const perimeter = attached ? length + 2 * width : 2 * (length + width);
    const wallArea = perimeter * height;
    const roofArea = length * width;
    const meshRate = catioPricing.meshWallRates[mesh];
    const roofRate = catioPricing.roofRates[roof];

    const items = [
      { label: "Base fee (design, hardware, travel)", amount: catioPricing.baseFee },
      {
        label: `Walls: ${Math.round(wallArea)} sq ft × ${meshRate.label}`,
        amount: wallArea * meshRate.perSqFt,
      },
    ];
    if (roofRate.perSqFt > 0) {
      items.push({
        label: `Roof: ${Math.round(roofArea)} sq ft × ${roofRate.label}`,
        amount: roofArea * roofRate.perSqFt,
      });
    }
    if (bends > 0)
      items.push({ label: `${bends} bend(s) / corner(s)`, amount: bends * catioPricing.perBend });
    if (doors > 0)
      items.push({ label: `${doors} access door(s)`, amount: doors * catioPricing.perDoor });

    const total = items.reduce((s, i) => s + i.amount, 0);
    return { items, total, wallArea, roofArea };
  }, [length, width, height, bends, doors, attached, mesh, roof]);

  const low = Math.round(est.total * (1 - TOLERANCE));
  const high = Math.round(est.total * (1 + TOLERANCE));

  const mailtoHref = useMemo(() => {
    const body = [
      "Hi Daan,",
      "",
      "I configured this catio on your website and would like a quote:",
      "",
      `- Footprint: ${length} ft x ${width} ft, ${height} ft tall`,
      `- ${attached ? "Attached to the house" : "Freestanding"}`,
      `- Mesh: ${catioPricing.meshWallRates[mesh].label}`,
      `- Roof: ${catioPricing.roofRates[roof].label}`,
      `- Bends/corners: ${bends}, doors: ${doors}`,
      "",
      `Estimated range: ${usd(low)} - ${usd(high)}`,
      "",
      "Name:",
      "Phone:",
      "Address:",
    ].join("\n");
    return `mailto:${siteConfig.contactEmail}?subject=${encodeURIComponent(
      "Catio quote request"
    )}&body=${encodeURIComponent(body)}`;
  }, [length, width, height, bends, doors, attached, mesh, roof, low, high]);

  const numberField = (
    label: string,
    value: number,
    setValue: (n: number) => void,
    max: number,
    unit: string,
    min = 0
  ) => (
    <label className="block">
      <span className="text-sm font-medium text-emerald-950">{label}</span>
      <div className="mt-1 flex items-center gap-2">
        <input
          type="number"
          min={min}
          max={max}
          value={value}
          onChange={(e) =>
            setValue(Math.max(min, Math.min(max, Number(e.target.value) || 0)))
          }
          className="w-24 rounded-lg border border-emerald-300 bg-white px-3 py-2 text-sm text-emerald-950 focus:border-emerald-600 focus:outline-none"
        />
        <span className="text-sm text-emerald-800">{unit}</span>
      </div>
    </label>
  );

  return (
    <div className="grid gap-8 lg:grid-cols-[1fr_20rem]">
      <div className="space-y-6">
        <div className="rounded-xl border border-emerald-200 bg-white p-5">
          <h3 className="font-semibold text-emerald-950">Dimensions</h3>
          <div className="mt-3 grid grid-cols-2 gap-4 sm:grid-cols-3">
            {numberField("Length", length, setLength, limits.maxLength, "ft", 1)}
            {numberField("Width", width, setWidth, limits.maxWidth, "ft", 1)}
            {numberField("Height", height, setHeight, limits.maxHeight, "ft", 1)}
          </div>
        </div>

        <div className="rounded-xl border border-emerald-200 bg-white p-5">
          <h3 className="font-semibold text-emerald-950">Layout</h3>
          <div className="mt-3 grid grid-cols-2 gap-4">
            {numberField("Bends / corners", bends, setBends, limits.maxBends, "")}
            {numberField("Access doors", doors, setDoors, limits.maxDoors, "")}
          </div>
          <label className="mt-4 flex items-center gap-2">
            <input
              type="checkbox"
              checked={attached}
              onChange={(e) => setAttached(e.target.checked)}
              className="accent-emerald-600"
            />
            <span className="text-sm text-emerald-950">
              Attached to the house (one long side uses your wall — cheaper)
            </span>
          </label>
        </div>

        <div className="rounded-xl border border-emerald-200 bg-white p-5">
          <h3 className="font-semibold text-emerald-950">Materials</h3>
          <div className="mt-3 grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="text-sm font-medium text-emerald-950">Mesh type</span>
              <select
                value={mesh}
                onChange={(e) => setMesh(e.target.value as MeshKey)}
                className="mt-1 w-full rounded-lg border border-emerald-300 bg-white px-3 py-2 text-sm text-emerald-950 focus:border-emerald-600 focus:outline-none"
              >
                {Object.entries(catioPricing.meshWallRates).map(([key, r]) => (
                  <option key={key} value={key}>
                    {r.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="text-sm font-medium text-emerald-950">Roof</span>
              <select
                value={roof}
                onChange={(e) => setRoof(e.target.value as RoofKey)}
                className="mt-1 w-full rounded-lg border border-emerald-300 bg-white px-3 py-2 text-sm text-emerald-950 focus:border-emerald-600 focus:outline-none"
              >
                {Object.entries(catioPricing.roofRates).map(([key, r]) => (
                  <option key={key} value={key}>
                    {r.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </div>
      </div>

      <aside className="lg:sticky lg:top-6 h-fit rounded-xl border border-emerald-300 bg-white p-5 shadow-sm">
        <h3 className="text-base font-semibold text-emerald-950">Your catio</h3>
        <ul className="mt-3 space-y-1.5 text-sm">
          {est.items.map((i) => (
            <li key={i.label} className="flex justify-between gap-3">
              <span className="text-emerald-900">{i.label}</span>
              <span className="shrink-0 text-emerald-700">{usd(i.amount)}</span>
            </li>
          ))}
        </ul>
        <div className="mt-4 border-t border-emerald-200 pt-4">
          <div className="flex items-baseline justify-between">
            <span className="text-sm font-medium text-emerald-950">Estimated range</span>
            <span className="text-lg font-bold text-emerald-700">
              {usd(low)}–{usd(high)}
            </span>
          </div>
          <p className="mt-2 text-xs leading-relaxed text-emerald-800/70">
            Ballpark estimate (±15%) — final pricing depends on site conditions,
            materials and finish. A free on-site measure comes before any quote.
          </p>
          <a
            href={mailtoHref}
            className="mt-4 block rounded-lg bg-emerald-700 px-4 py-2.5 text-center text-sm font-semibold text-white transition-colors hover:bg-emerald-600"
          >
            Request a free quote
          </a>
        </div>
      </aside>
    </div>
  );
}
