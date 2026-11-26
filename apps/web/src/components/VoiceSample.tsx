"use client";
// A sample of a voice call with Nora, as it looks in the app: her portrait, live captions of both sides, and the
// Confirm button that alone books. Scripted (a website visitor is not signed in); real calls run in the app.
import Image from "next/image";
import { useEffect, useState } from "react";

const LINES: { who: "you" | "nora"; text: string }[] = [
  { who: "you", text: "Hi Nora, I'm Michelle. When does Quincy open on Saturday?" },
  { who: "nora", text: "Quincy is open on Saturday from 07:00 to 20:00." },
  { who: "you", text: "Can I get a cleaning there this Saturday?" },
  { who: "nora", text: "The first free time is Saturday at 13:00. Shall I book it? Please press Confirm on your screen." },
];

export default function VoiceSample() {
  const [shown, setShown] = useState(LINES.length + 1);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    setShown(0);
    setPlaying(true);
  }, []);
  useEffect(() => {
    if (!playing) return;
    if (shown > LINES.length) { setPlaying(false); return; }
    const t = setTimeout(() => setShown((n) => n + 1), shown === 0 ? 600 : 2600);
    return () => clearTimeout(t);
  }, [shown, playing]);

  const speaking = playing && LINES[shown - 1]?.who === "nora";
  return (
    <div className="mx-auto w-full max-w-[340px] rounded-[2.75rem] bg-sea p-3 shadow-2xl ring-1 ring-black/10">
      <div className="overflow-hidden rounded-[2.2rem] bg-gradient-to-b from-[#1a8e7e] via-[#0c4c46] to-[#072b29] px-5 pb-6 pt-8 text-white">
        <p className="text-center text-xs font-semibold text-white/70">Voice call · Sample</p>
        <div className="relative mx-auto mt-5 size-32">
          <span aria-hidden className={`absolute inset-0 rounded-full bg-shine/30 ${speaking ? "animate-ping" : ""}`} />
          <Image src={speaking ? "/images/nora/speaking.png" : "/images/nora/listening.png"} alt="Nora" fill sizes="128px"
            className="rounded-full bg-enamel object-cover ring-4 ring-white/20" />
        </div>
        <p className="mt-4 text-center text-lg font-extrabold">Nora</p>
        <p className="text-center text-xs text-white/70">{speaking ? "Speaking…" : playing ? "Listening…" : "AI receptionist"}</p>
        <div aria-hidden className="mx-auto mt-3 flex h-6 items-end justify-center gap-1">
          {[0, 1, 2, 3, 4, 5, 6].map((i) => (
            <span key={i} className="w-1 rounded-full bg-shine transition-all duration-300"
              style={{ height: playing ? `${6 + ((i * 7 + shown * 5) % 18)}px` : "6px" }} />
          ))}
        </div>
        <ol className="mt-5 min-h-[220px] space-y-2 text-sm" aria-label="Captions">
          {LINES.slice(0, shown).map((l) => (
            <li key={l.text} className={`w-fit max-w-[90%] rounded-2xl px-3 py-2 ${l.who === "you" ? "ml-auto rounded-br-md bg-white/15" : "rounded-bl-md bg-white text-sea"}`}>
              {l.text}
            </li>
          ))}
        </ol>
        {shown > LINES.length && (
          <div className="mt-3 rounded-2xl bg-white p-3 text-sea">
            <p className="text-sm font-extrabold">Book this visit?</p>
            <p className="text-xs text-muted">Adult cleaning · Saturday 13:00 · Quincy</p>
            <div className="mt-2 grid grid-cols-2 gap-2 text-xs font-bold">
              <span className="rounded-full py-2 text-center ring-1 ring-line">Not now</span>
              <span className="rounded-full bg-teal py-2 text-center text-white">Confirm</span>
            </div>
          </div>
        )}
        <div className="mt-5 flex justify-center gap-4" aria-hidden>
          <span className="grid size-12 place-items-center rounded-full bg-white/15 text-xs">Mute</span>
          <span className="grid size-12 place-items-center rounded-full bg-danger text-xs font-bold">End</span>
        </div>
      </div>
      <button onClick={() => { setShown(0); setPlaying(true); }} className="mx-auto mt-3 block text-xs font-semibold text-white/80 hover:text-white">
        Play the sample again
      </button>
    </div>
  );
}
