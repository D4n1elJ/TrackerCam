import type { Metadata } from "next";
import Link from "next/link";
import SimConfigurator from "@/components/SimConfigurator";
import { simPricing } from "@/data/sim-pricing";

export const metadata: Metadata = {
  title: "Joustra SimWorks — Pro-Enthusiast Driving Simulators",
  description:
    "Turnkey sim racing rigs built on Trak Racer, Simucube and Heusinkveld hardware. Configure your rig and get an instant ±15% estimate.",
};

export default function SimulatorsPage() {
  return (
    <div className="flex-1 bg-zinc-950 text-zinc-100">
      <nav className="border-b border-zinc-800">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <Link href="/" className="text-sm text-zinc-400 hover:text-white">
            ← Joustra Builds
          </Link>
          <span className="text-sm font-semibold uppercase tracking-[0.2em] text-red-500">
            Joustra SimWorks
          </span>
        </div>
      </nav>

      <header className="border-b border-zinc-800 bg-[radial-gradient(ellipse_at_top,rgba(220,38,38,0.15),transparent_60%)]">
        <div className="mx-auto max-w-6xl px-6 py-16">
          <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
            Driving simulators,
            <br />
            <span className="text-red-500">built like race cars.</span>
          </h1>
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-zinc-400">
            I design, assemble and tune pro-enthusiast sim rigs using the gear
            serious drivers trust: Trak Racer chassis, Simucube direct-drive
            wheelbases, Heusinkveld pedals and more. Delivered assembled,
            calibrated and ready to race.
          </p>
          <div className="mt-8 flex flex-wrap gap-6 text-sm text-zinc-500">
            <span>Trak Racer</span>
            <span>Simucube</span>
            <span>Heusinkveld</span>
            <span>Cube Controls</span>
          </div>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-6 py-12">
        <div className="grid gap-6 sm:grid-cols-3">
          {[
            {
              t: "Spec'd to your driving",
              d: "GT3, formula, drifting or rally — the hardware mix follows how and what you race.",
            },
            {
              t: "Assembled & cable-managed",
              d: "Delivered as a finished rig: torqued, wired, hidden cabling, no zip-tie chaos.",
            },
            {
              t: "Tuned, not just built",
              d: "Force feedback, pedal calibration and screen FOV set up properly before handover.",
            },
          ].map((f) => (
            <div key={f.t} className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
              <h3 className="font-semibold text-white">{f.t}</h3>
              <p className="mt-2 text-sm leading-relaxed text-zinc-400">{f.d}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-6 pb-20">
        <div className="mb-8 border-t border-zinc-800 pt-12">
          <h2 className="text-2xl font-bold tracking-tight text-white">
            Configure your rig
          </h2>
          <p className="mt-2 max-w-2xl text-zinc-400">
            Pick your parts to get a live ballpark estimate — ±15% around current
            supplier pricing ({simPricing.asOf}). Like what you see? Send it over
            and I&apos;ll turn it into a firm quote.
          </p>
        </div>
        <SimConfigurator />
      </section>

      <footer className="border-t border-zinc-800 py-8 text-center text-sm text-zinc-600">
        Joustra SimWorks is part of{" "}
        <Link href="/" className="text-zinc-400 hover:text-white">
          Joustra Builds
        </Link>
        . Not affiliated with the hardware brands listed.
      </footer>
    </div>
  );
}
