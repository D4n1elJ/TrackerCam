import Link from "next/link";
import { siteConfig } from "@/data/site-config";

const projects = [
  {
    title: "Custom deck & pergola",
    tag: "Outdoor",
    text: "Ground-level cedar deck with an integrated pergola and built-in seating.",
  },
  {
    title: "Garage workshop fit-out",
    tag: "Interior",
    text: "Full wall of workbenches, French-cleat tool storage and dust-managed power runs.",
  },
  {
    title: "Backyard catio",
    tag: "Catio",
    text: "A 12-foot enclosed patio run so the cats can enjoy the outdoors safely.",
  },
  {
    title: "Triple-screen sim rig",
    tag: "Simulator",
    text: "Simucube-powered racing simulator on an aluminium-profile chassis, built and tuned end to end.",
  },
];

export default function Home() {
  return (
    <div className="flex-1 bg-stone-100 text-stone-900">
      {/* Hero */}
      <header className="border-b border-stone-300 bg-stone-900 text-stone-100">
        <div className="mx-auto max-w-5xl px-6 py-20">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-400">
            Small projects, built right
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-6xl">
            Joustra <span className="text-amber-400">Builds</span>
          </h1>
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-stone-300">
            Hi, I&apos;m {siteConfig.ownerName}. I take on small construction and
            fabrication projects — decks, fit-outs, custom enclosures and the odd
            thing nobody else wants to build. Careful work, honest estimates, no
            surprises.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <a
              href={`mailto:${siteConfig.contactEmail}?subject=${encodeURIComponent("Project inquiry")}`}
              className="rounded-lg bg-amber-500 px-5 py-2.5 text-sm font-semibold text-stone-900 transition-colors hover:bg-amber-400"
            >
              Start a project
            </a>
            <a
              href="#specialties"
              className="rounded-lg border border-stone-600 px-5 py-2.5 text-sm font-semibold text-stone-200 transition-colors hover:border-stone-400"
            >
              See specialties
            </a>
          </div>
        </div>
      </header>

      {/* Specialties: the two sub-brands */}
      <section id="specialties" className="mx-auto max-w-5xl px-6 py-16">
        <h2 className="text-2xl font-bold tracking-tight">Two things I build a lot of</h2>
        <p className="mt-2 max-w-2xl text-stone-600">
          Alongside general small builds, I run two dedicated services — each with
          its own configurator so you can get an instant ballpark price.
        </p>
        <div className="mt-8 grid gap-6 md:grid-cols-2">
          <Link
            href="/simulators"
            className="group relative overflow-hidden rounded-2xl bg-zinc-950 p-8 text-white transition-transform hover:-translate-y-1"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-red-500">
              Joustra SimWorks
            </p>
            <h3 className="mt-2 text-2xl font-bold">
              Pro-enthusiast driving simulators
            </h3>
            <p className="mt-3 text-sm leading-relaxed text-zinc-400">
              Turnkey sim racing rigs built on Trak Racer chassis with Simucube
              direct drive and Heusinkveld pedals. Configure yours and get an
              instant estimate.
            </p>
            <span className="mt-6 inline-block text-sm font-semibold text-red-400 group-hover:text-red-300">
              Build your rig →
            </span>
          </Link>
          <Link
            href="/catio"
            className="group relative overflow-hidden rounded-2xl bg-emerald-900 p-8 text-white transition-transform hover:-translate-y-1"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-300">
              Joustra Catios
            </p>
            <h3 className="mt-2 text-2xl font-bold">Catios & pet-safe patios</h3>
            <p className="mt-3 text-sm leading-relaxed text-emerald-100/80">
              Custom-built enclosures that fence off your patio or yard so cats
              and dogs can be outside, safely. Size it up and get a real-time
              estimate.
            </p>
            <span className="mt-6 inline-block text-sm font-semibold text-emerald-300 group-hover:text-emerald-200">
              Design your catio →
            </span>
          </Link>
        </div>
      </section>

      {/* Projects */}
      <section className="border-t border-stone-200 bg-white">
        <div className="mx-auto max-w-5xl px-6 py-16">
          <h2 className="text-2xl font-bold tracking-tight">Recent projects</h2>
          <div className="mt-8 grid gap-6 sm:grid-cols-2">
            {projects.map((p) => (
              <article
                key={p.title}
                className="rounded-xl border border-stone-200 bg-stone-50 p-6"
              >
                <span className="inline-block rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-semibold text-amber-800">
                  {p.tag}
                </span>
                <h3 className="mt-3 font-semibold">{p.title}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-stone-600">{p.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* About */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <div className="grid gap-8 md:grid-cols-[2fr_1fr]">
          <div>
            <h2 className="text-2xl font-bold tracking-tight">About me</h2>
            <p className="mt-3 leading-relaxed text-stone-700">
              I&apos;m {siteConfig.ownerName} — a builder and tinkerer who likes
              projects at the intersection of craftsmanship and engineering.
              Whether it&apos;s framing a catio, tuning force feedback on a
              direct-drive wheelbase, or squaring up a deck, I sweat the details
              so you don&apos;t have to.
            </p>
            <p className="mt-3 leading-relaxed text-stone-700">
              Every project starts with a conversation and a clear estimate.
              Reach out and tell me what you&apos;re thinking.
            </p>
          </div>
          <div className="rounded-xl border border-stone-200 bg-white p-6">
            <h3 className="font-semibold">Get in touch</h3>
            <p className="mt-2 text-sm text-stone-600">{siteConfig.serviceArea}</p>
            <a
              href={`mailto:${siteConfig.contactEmail}`}
              className="mt-3 block break-all text-sm font-semibold text-amber-700 hover:text-amber-600"
            >
              {siteConfig.contactEmail}
            </a>
          </div>
        </div>
      </section>

      <footer className="border-t border-stone-200 bg-stone-900 py-8 text-center text-sm text-stone-400">
        © {new Date().getFullYear()} {siteConfig.businessName} ·{" "}
        <Link href="/simulators" className="hover:text-stone-200">
          SimWorks
        </Link>{" "}
        ·{" "}
        <Link href="/catio" className="hover:text-stone-200">
          Catios
        </Link>
      </footer>
    </div>
  );
}
