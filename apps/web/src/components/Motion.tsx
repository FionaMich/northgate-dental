"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText } from "gsap/SplitText";

gsap.registerPlugin(ScrollTrigger, SplitText);

/**
 * The site's motion, in one place. Pages mark elements with data attributes and this component animates them:
 *   data-split        a heading revealed word by word, each word flipping up in 3D
 *   data-reveal       a block that rises into view; its [data-reveal-item] children follow in turn
 *   data-tilt         a card that tilts towards the pointer in 3D, with a soft light following it
 *   data-flip         tiles that flip up from below in 3D as they scroll into view
 *   data-parallax     an element that drifts slower than the page (the value is the distance in pixels)
 *   data-float        an element that floats gently in depth
 * Nothing moves for people who ask their device for reduced motion, and everything is reverted on unmount.
 */
export function Motion() {
  const pathname = usePathname();   // the layout stays mounted between pages, so set up again on each one
  useEffect(() => {
    const mm = gsap.matchMedia();
    const cleanups: Array<() => void> = [];

    mm.add("(prefers-reduced-motion: no-preference)", () => {
      document.querySelectorAll<HTMLElement>("[data-split]").forEach((el) => {
        const split = SplitText.create(el, { type: "words", mask: "words" });
        gsap.set(el, { perspective: 700 });
        gsap.from(split.words, {
          yPercent: 110, rotationX: -70, transformOrigin: "50% 100%", opacity: 0,
          duration: 0.9, ease: "power4.out", stagger: 0.06, delay: 0.1,
          scrollTrigger: el.closest("[data-hero]") ? undefined : { trigger: el, start: "top 85%" },
        });
      });

      ScrollTrigger.batch("[data-reveal]", {
        start: "top 85%",
        once: true,
        onEnter: (blocks) => blocks.forEach((block) => {
          const items = block.querySelectorAll("[data-reveal-item]");
          gsap.fromTo(block, { y: 40, opacity: 0 }, { y: 0, opacity: 1, duration: 0.8, ease: "power3.out" });
          if (items.length) gsap.fromTo(items, { y: 50, opacity: 0, rotationX: 12, transformPerspective: 900 },
            { y: 0, opacity: 1, rotationX: 0, duration: 0.8, ease: "power3.out", stagger: 0.09, delay: 0.1 });
        }),
      });

      document.querySelectorAll<HTMLElement>("[data-flip]").forEach((group) => {
        gsap.from(group.children, {
          rotationX: -75, y: 30, opacity: 0, transformPerspective: 800, transformOrigin: "50% 0%",
          duration: 0.9, ease: "back.out(1.4)", stagger: { each: 0.08, from: "start" },
          scrollTrigger: { trigger: group, start: "top 80%" },
        });
      });

      document.querySelectorAll<HTMLElement>("[data-parallax]").forEach((el) => {
        const distance = Number(el.dataset.parallax) || 60;
        gsap.fromTo(el, { y: -distance / 2 }, {
          y: distance / 2, ease: "none",
          scrollTrigger: { trigger: el.parentElement ?? el, start: "top bottom", end: "bottom top", scrub: true },
        });
      });

      document.querySelectorAll<HTMLElement>("[data-float]").forEach((el, i) => {
        gsap.to(el, { y: -10, rotationY: 6, rotationX: -3, transformPerspective: 900, duration: 3.2 + i * 0.4, ease: "sine.inOut", yoyo: true, repeat: -1 });
      });

      // The app panel tips back in 3D as it scrolls in, and settles flat when centred.
      document.querySelectorAll<HTMLElement>("[data-tip]").forEach((el) => {
        gsap.fromTo(el, { rotationX: 18, scale: 0.94, transformPerspective: 1200, transformOrigin: "50% 100%" }, {
          rotationX: 0, scale: 1, ease: "none",
          scrollTrigger: { trigger: el, start: "top bottom", end: "center center", scrub: 0.6 },
        });
      });
    });

    // Tilt works with a mouse or trackpad only: touch screens keep their normal scrolling.
    mm.add("(prefers-reduced-motion: no-preference) and (hover: hover) and (pointer: fine)", () => {
      document.querySelectorAll<HTMLElement>("[data-tilt]").forEach((card) => {
        card.style.transformStyle = "preserve-3d";
        const glare = document.createElement("span");
        glare.setAttribute("aria-hidden", "true");
        glare.className = "tilt-glare";
        card.appendChild(glare);
        // overwrite "auto" replaces only an earlier rotation, never the reveal's fade still running on the same card
        const tilt = (x: number, y: number) =>
          gsap.to(card, { rotationX: y, rotationY: x, transformPerspective: 900, duration: 0.5, ease: "power3.out", overwrite: "auto" });
        const move = (e: PointerEvent) => {
          const r = card.getBoundingClientRect();
          const x = (e.clientX - r.left) / r.width - 0.5;
          const y = (e.clientY - r.top) / r.height - 0.5;
          tilt(x * 10, -y * 10);
          glare.style.background = `radial-gradient(circle at ${(x + 0.5) * 100}% ${(y + 0.5) * 100}%, rgba(255,255,255,0.35), transparent 55%)`;
          glare.style.opacity = "1";
        };
        const leave = () => { tilt(0, 0); glare.style.opacity = "0"; };
        card.addEventListener("pointermove", move);
        card.addEventListener("pointerleave", leave);
        cleanups.push(() => {
          card.removeEventListener("pointermove", move);
          card.removeEventListener("pointerleave", leave);
          glare.remove();
        });
      });
    });

    return () => {
      cleanups.forEach((fn) => fn());
      mm.revert();
    };
  }, [pathname]);

  return null;
}
