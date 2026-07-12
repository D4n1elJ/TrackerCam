"use client";

import { useMemo, useState } from "react";
import { simPricing, PRICE_TOLERANCE } from "@/data/sim-pricing";
import { siteConfig } from "@/data/site-config";

const usd = (n: number) =>
  n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  });

type Selections = Record<string, string[]>;

function defaultSelections(): Selections {
  const sel: Selections = {};
  for (const cat of simPricing.categories) {
    sel[cat.id] = cat.multi ? [] : [cat.options[0].id];
  }
  return sel;
}

export default function SimConfigurator() {
  const [selections, setSelections] = useState<Selections>(defaultSelections);

  const toggle = (catId: string, optId: string, multi: boolean) => {
    setSelections((prev) => {
      const current = prev[catId] ?? [];
      if (!multi) return { ...prev, [catId]: [optId] };
      return {
        ...prev,
        [catId]: current.includes(optId)
          ? current.filter((id) => id !== optId)
          : [...current, optId],
      };
    });
  };

  const { lines, total } = useMemo(() => {
    const lines: { category: string; label: string; price: number }[] = [];
    for (const cat of simPricing.categories) {
      for (const optId of selections[cat.id] ?? []) {
        const opt = cat.options.find((o) => o.id === optId);
        if (opt && opt.price > 0) {
          lines.push({ category: cat.name, label: opt.label, price: opt.price });
        }
      }
    }
    return { lines, total: lines.reduce((s, l) => s + l.price, 0) };
  }, [selections]);

  const low = Math.round(total * (1 - PRICE_TOLERANCE));
  const high = Math.round(total * (1 + PRICE_TOLERANCE));

  const mailtoHref = useMemo(() => {
    const body = [
      "Hi Daan,",
      "",
      "I configured this sim rig on your website and would like a quote:",
      "",
      ...lines.map((l) => `- ${l.category}: ${l.label} (~${usd(l.price)})`),
      "",
      `Estimated range: ${usd(low)} - ${usd(high)}`,
      "",
      "Name:",
      "Phone:",
      "Location:",
    ].join("\n");
    return `mailto:${siteConfig.contactEmail}?subject=${encodeURIComponent(
      "Sim rig quote request"
    )}&body=${encodeURIComponent(body)}`;
  }, [lines, low, high]);

  return (
    <div className="grid gap-8 lg:grid-cols-[1fr_20rem]">
      <div className="space-y-8">
        {simPricing.categories.map((cat) => (
          <fieldset key={cat.id}>
            <legend className="text-lg font-semibold text-white">
              {cat.name}
              {!cat.required && (
                <span className="ml-2 text-xs font-normal uppercase tracking-wider text-zinc-500">
                  optional
                </span>
              )}
            </legend>
            <p className="mt-1 text-sm text-zinc-400">{cat.blurb}</p>
            <div className="mt-3 grid gap-2 sm:grid-cols-2">
              {cat.options.map((opt) => {
                const checked = (selections[cat.id] ?? []).includes(opt.id);
                return (
                  <label
                    key={opt.id}
                    className={`flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition-colors ${
                      checked
                        ? "border-red-500 bg-red-500/10"
                        : "border-zinc-700 bg-zinc-900 hover:border-zinc-500"
                    }`}
                  >
                    <input
                      type={cat.multi ? "checkbox" : "radio"}
                      name={cat.id}
                      checked={checked}
                      onChange={() => toggle(cat.id, opt.id, cat.multi)}
                      className="mt-1 accent-red-500"
                    />
                    <span className="flex-1">
                      <span className="block text-sm font-medium text-white">
                        {opt.label}
                      </span>
                      {opt.note && (
                        <span className="block text-xs text-zinc-400">{opt.note}</span>
                      )}
                      <span className="mt-0.5 block text-xs text-zinc-500">
                        {opt.supplier !== "—" && `${opt.supplier} · `}
                        {opt.price > 0 ? `~${usd(opt.price)}` : "included / your own"}
                      </span>
                    </span>
                  </label>
                );
              })}
            </div>
          </fieldset>
        ))}
      </div>

      <aside className="lg:sticky lg:top-6 h-fit rounded-xl border border-zinc-700 bg-zinc-900 p-5">
        <h3 className="text-base font-semibold text-white">Your build</h3>
        <ul className="mt-3 space-y-1.5 text-sm">
          {lines.length === 0 && (
            <li className="text-zinc-500">Nothing priced yet — pick your parts.</li>
          )}
          {lines.map((l) => (
            <li key={l.category + l.label} className="flex justify-between gap-3">
              <span className="text-zinc-300">{l.label}</span>
              <span className="shrink-0 text-zinc-400">{usd(l.price)}</span>
            </li>
          ))}
        </ul>
        <div className="mt-4 border-t border-zinc-700 pt-4">
          <div className="flex justify-between text-sm text-zinc-400">
            <span>Parts subtotal</span>
            <span>{usd(total)}</span>
          </div>
          <div className="mt-2 flex items-baseline justify-between">
            <span className="text-sm font-medium text-zinc-200">Estimated range</span>
            <span className="text-lg font-bold text-red-400">
              {usd(low)}–{usd(high)}
            </span>
          </div>
          <p className="mt-2 text-xs leading-relaxed text-zinc-500">
            Rough estimate of ±15% around supplier list prices ({simPricing.asOf}).
            Excludes shipping, taxes and assembly. Final quote follows after a
            short intake call.
          </p>
          <a
            href={mailtoHref}
            className="mt-4 block rounded-lg bg-red-600 px-4 py-2.5 text-center text-sm font-semibold text-white transition-colors hover:bg-red-500"
          >
            Request a quote
          </a>
        </div>
      </aside>
    </div>
  );
}
