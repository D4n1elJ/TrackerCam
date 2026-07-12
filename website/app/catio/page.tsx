import type { Metadata } from "next";
import Link from "next/link";
import CatioConfigurator from "@/components/CatioConfigurator";

export const metadata: Metadata = {
  title: "Joustra Catios — Safe Outdoor Spaces for Cats & Dogs",
  description:
    "Custom catios and pet-safe patio enclosures. Enter your dimensions and get a real-time ballpark estimate.",
};

export default function CatioPage() {
  return (
    <div className="flex-1 bg-emerald-50 text-emerald-950">
      <nav className="border-b border-emerald-200 bg-white/70">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <Link href="/" className="text-sm text-emerald-700 hover:text-emerald-950">
            ← Joustra Builds
          </Link>
          <span className="text-sm font-semibold uppercase tracking-[0.2em] text-emerald-700">
            Joustra Catios
          </span>
        </div>
      </nav>

      <header className="bg-emerald-900 text-white">
        <div className="mx-auto max-w-6xl px-6 py-16">
          <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
            The outdoors, <span className="text-emerald-300">without the worry.</span>
          </h1>
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-emerald-100/90">
            Catios are enclosed outdoor spaces that let your cats — or dogs —
            enjoy fresh air, sunshine and birdwatching, safely. I build them
            custom to your patio, deck or yard: framed in wood, wrapped in
            escape-proof mesh, and finished to look like part of the house.
          </p>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-6 py-12">
        <div className="grid gap-6 sm:grid-cols-3">
          {[
            {
              t: "Built for your space",
              d: "Window-box, patio wrap or full walk-in run — sized and shaped around what you have.",
            },
            {
              t: "Escape-proof & predator-proof",
              d: "Galvanized or heavy-duty welded mesh, secure doors, no gaps. Dogs and diggers included.",
            },
            {
              t: "Looks like it belongs",
              d: "Clean framing, stained or painted to match, with shelves and perches your pets will actually use.",
            },
          ].map((f) => (
            <div key={f.t} className="rounded-xl border border-emerald-200 bg-white p-6">
              <h3 className="font-semibold">{f.t}</h3>
              <p className="mt-2 text-sm leading-relaxed text-emerald-900/70">{f.d}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-6 pb-20">
        <div className="mb-8 border-t border-emerald-200 pt-12">
          <h2 className="text-2xl font-bold tracking-tight">Size up your catio</h2>
          <p className="mt-2 max-w-2xl text-emerald-900/70">
            Enter rough dimensions to get a real-time ballpark estimate (±15%).
            Every project still gets a free on-site measure before a firm quote.
          </p>
        </div>
        <CatioConfigurator />
      </section>

      <footer className="border-t border-emerald-200 bg-white py-8 text-center text-sm text-emerald-800/60">
        Joustra Catios is part of{" "}
        <Link href="/" className="text-emerald-700 hover:text-emerald-950">
          Joustra Builds
        </Link>
        .
      </footer>
    </div>
  );
}
