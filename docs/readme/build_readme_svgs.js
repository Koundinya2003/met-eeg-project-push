// Builds the animated SVG panels shown in README.md from paper/one_sheeter.html.
// GitHub strips CSS and scripts from READMEs, so each section of the one sheet
// is rendered with Playwright, frozen into XHTML, given CSS animations and
// subsetted Google Fonts (embedded as data URIs), and wrapped in an SVG
// foreignObject. A light and a dark version are written for every panel.
//
// Usage (from the project folder):  node docs/readme/build_readme_svgs.js
// Needs Playwright with Chromium, curl, and network access to Google Fonts.

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "..", "..");
const SRC = path.join(ROOT, "paper", "one_sheeter.html");
const OUT = __dirname;
const WIDTH = 960;
const FONT_CSS =
  "https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@400;600;800" +
  "&family=Newsreader:ital,wght@0,400;0,500;1,400" +
  "&family=JetBrains+Mono:wght@400;600&display=swap";
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

// Panels: which parts of the one sheet go into each image.
const GROUPS = [
  { file: "01_masthead", alt: "The Song or the Self? A preregistered search for personal musical emotion in scalp EEG. Verdict: 0 of 3 hypotheses supported.", pick: ["header.mast", "section.verdict"] },
  { file: "02_setup", alt: "The setup: 20 listeners, 20 songs, 66 EEG channels, 395 trials. The key move: each rating is split into a song consensus and a personal deviation.", grid: [0, 1] },
  { file: "03_bets", alt: "Three preregistered bets, H1, H2 and H3, all not supported. Every confidence interval crosses zero.", grid: [2] },
  { file: "04_variance", alt: "Ratings are mostly the song, alpha is mostly the person. 105 exploratory tests: 3 uncorrected hits, about 5 expected by chance, 0 survived correction.", grid: [3, 4] },
  { file: "05_robustness", alt: "Why the null still says something, a lesson in counting, and robustness checks that all stayed null.", grid: [5, 6, 7] },
  { file: "06_why", alt: "Why the textbook effects may have vanished, and what this study does not show.", grid: [8, 9] },
  { file: "07_next", alt: "The next experiment in four moves, plus data and code sources.", grid: [10], footer: true },
];

const DARK_TOKENS = `--paper: #0f1714; --grid: #17241f; --grid-major: #1e2f28; --ink: #e4ece6; --muted: #98aaa0;
  --panel: #131e1a; --rule: #2c4038; --song: #7fa7e8; --self: #f08068; --pen: #f08068; --faint: #1b2924;`;

// Motion that survives inside an <img>: CSS animations only.
const MOTION_CSS = `
.root { overflow: hidden; }
.sheet { padding-block: 12px; }
@keyframes scroll { to { transform: translateX(-400px); } }
.traces svg g.scroll { animation: scroll 12s linear infinite; }
@keyframes blink { 50% { opacity: 0; } }
.cursor { animation: blink 1.1s steps(1) infinite; }
.rec { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: var(--pen); margin-right: 6px; vertical-align: 0; animation: blink 1.4s steps(1) infinite; }
@keyframes thump { 0% { transform: rotate(var(--tilt)) scale(1.9); opacity: 0; } 60% { transform: rotate(var(--tilt)) scale(0.94); opacity: 1; } 100% { transform: rotate(var(--tilt)) scale(1); opacity: 1; } }
.stamp { --tilt: -3deg; animation: thump 0.55s cubic-bezier(.2,.8,.3,1.2) 0.7s both; }
.bet .no { --tilt: -2deg; animation: thump 0.5s cubic-bezier(.2,.8,.3,1.2) both; }
.bet:nth-child(1) .no { animation-delay: 0.5s; }
.bet:nth-child(2) .no { animation-delay: 0.8s; }
.bet:nth-child(3) .no { animation-delay: 1.1s; }
@keyframes wipe { from { clip-path: inset(0 100% 0 0); } to { clip-path: inset(0 0 0 0); } }
.bar { animation: wipe 1.2s cubic-bezier(.3,.7,.2,1) both; }
.vrow:nth-child(1) .bar { animation-delay: 0.3s; }
.vrow:nth-child(2) .bar { animation-delay: 0.6s; }
.vrow:nth-child(3) .bar { animation-delay: 0.9s; }
.forest { animation: wipe 1.6s cubic-bezier(.3,.7,.2,1) 1.4s both; }
@keyframes pop { 0% { transform: scale(0); } 70% { transform: scale(1.4); } 100% { transform: scale(1); } }
.forest circle { transform-box: fill-box; transform-origin: center; animation: pop 0.45s ease-out both; }
@keyframes scan { 0% { background: var(--ink); border-color: var(--ink); } }
.m-panel i { animation: scan 0.6s ease-out var(--d) both; }
@keyframes ping { 0% { box-shadow: 0 0 0 0 var(--pen); } 100% { box-shadow: 0 0 0 9px transparent; } }
.m-panel i.hit { animation: scan 0.6s ease-out var(--d) both, ping 1.8s ease-out 2.6s infinite; }
@keyframes rise { from { opacity: 0; transform: translateY(8px); } }
.tally div { animation: rise 0.6s ease-out both; }
.tally div:nth-child(1) { animation-delay: 2.2s; }
.tally div:nth-child(2) { animation-delay: 2.5s; }
.tally div:nth-child(3) { animation-delay: 2.8s; }
.marker.mine { animation: slide 1.4s cubic-bezier(.3,.7,.2,1) 0.4s both; }
@keyframes slide { from { left: 56.25%; } }
.gap { animation: grow 1.4s cubic-bezier(.3,.7,.2,1) 0.4s both; }
@keyframes grow { from { width: 0; } }
@media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation: none !important; } }
`;

function cssFromPage(html, dark) {
  let css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  // drop the theme switch blocks, the responsive and print rules
  css = css.replace(/@media \(prefers-color-scheme: dark\)[\s\S]*?:root\[data-theme="dark"\] \{[\s\S]*?\}\n/, "");
  css = css.replace(/\/\* ---------- responsive ---------- \*\/[\s\S]*$/, "");
  css = css.replace(":root {", ".root {").replace("body {", ".root {");
  if (dark) css += `\n.root { ${DARK_TOKENS} color-scheme: dark; }\n`;
  return css + MOTION_CSS;
}

function fontFaces(text) {
  const chars = Array.from(new Set(Array.from(text + "0123456789 .,"))).join("");
  const url = FONT_CSS + "&text=" + encodeURIComponent(chars);
  const css = execFileSync("curl", ["-sS", "-A", UA, url]).toString();
  // Google serves one variable file for several weights; embed each file once with a weight range.
  const faces = new Map();
  for (const block of css.match(/@font-face \{[\s\S]*?\}/g) || []) {
    const fam = block.match(/font-family: '([^']+)'/)[1];
    const style = block.match(/font-style: (\w+)/)[1];
    const weight = +block.match(/font-weight: (\d+)/)[1];
    const u = block.match(/url\((https:[^)]+)\)/)[1];
    const key = fam + "|" + style + "|" + u;
    const f = faces.get(key) || { fam, style, u, lo: weight, hi: weight };
    f.lo = Math.min(f.lo, weight); f.hi = Math.max(f.hi, weight);
    faces.set(key, f);
  }
  let out = "";
  for (const f of faces.values()) {
    const buf = execFileSync("curl", ["-sS", "-A", UA, f.u]);
    out += `@font-face { font-family: '${f.fam}'; font-style: ${f.style}; font-weight: ${f.lo} ${f.hi}; src: url(data:font/woff2;base64,${buf.toString("base64")}) format('woff2'); }\n`;
  }
  return out;
}

(async () => {
  const html = fs.readFileSync(SRC, "utf8");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: WIDTH, height: 1200 } });
  // freeze the page's own script animation; the SVGs animate with CSS instead
  await page.addInitScript(() => { window.matchMedia = () => ({ matches: true, addListener() {}, addEventListener() {} }); });
  await page.setContent("<!doctype html><html><head><meta charset=\"utf-8\"></head><body>" + html + "</body></html>", { waitUntil: "load" });

  // Loop friendly traces: every component repeats every 400 units, so the scroll has no seam.
  await page.evaluate(() => {
    function rng(seed) { return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }; }
    const mk = (seed) => { const r = rng(seed), a = []; for (let i = 0; i < 200; i++) a.push(r() - 0.5); return a; };
    const nA = mk(7), nB = mk(19);
    const nz = (a, x) => a[Math.floor(x / 2) % 200];
    const fns = {
      "trace-song": (x) => (0.55 + 0.45 * Math.sin(2 * Math.PI * x / 400)) * (19 * Math.sin(2 * Math.PI * x / 25) + 6 * Math.sin(2 * Math.PI * x / 8)) + 3 * nz(nA, x),
      "trace-self": (x) => 2.2 * Math.sin(2 * Math.PI * x / 25) + 7 * nz(nB, x),
    };
    for (const id in fns) {
      const svg = document.getElementById(id);
      let d = "";
      for (let x = 0; x <= 800; x += 2) d += (x ? "L" : "M") + x + " " + (31 - fns[id](x)).toFixed(2) + " ";
      const g = svg.querySelector("g");
      g.removeAttribute("transform");
      g.setAttribute("class", "scroll");
      g.querySelector("path").setAttribute("d", d);
      svg.querySelectorAll(".pen-dot").forEach((c) => c.remove());
      const color = id === "trace-song" ? "var(--song)" : "var(--self)";
      const cur = document.createElementNS("http://www.w3.org/2000/svg", "line");
      for (const [k, v] of Object.entries({ x1: 398, y1: 4, x2: 398, y2: 58, stroke: color, "stroke-width": 2, class: "cursor" })) cur.setAttribute(k, v);
      svg.appendChild(cur);
    }
    const b = document.querySelector(".kicker b");
    const rec = document.createElement("i");
    rec.className = "rec";
    b.prepend(rec);
    document.querySelectorAll(".forest circle").forEach((c, i) => c.style.animationDelay = (2.4 + i * 0.25) + "s");
    document.querySelectorAll(".m-panel").forEach((p, pi) => p.querySelectorAll("i").forEach((d, i) => d.style.setProperty("--d", (0.2 + pi * 0.5 + i * 0.03).toFixed(2) + "s")));
  });

  const measure = await browser.newPage({ viewport: { width: WIDTH, height: 1200 } });

  for (const g of GROUPS) {
    const body = await page.evaluate((g) => {
      const main = document.createElement("main");
      main.className = "sheet";
      if (g.pick) g.pick.forEach((s) => main.appendChild(document.querySelector(s).cloneNode(true)));
      if (g.grid) {
        const grid = document.createElement("div");
        grid.className = "grid";
        const panels = document.querySelectorAll(".grid > .panel");
        g.grid.forEach((i) => grid.appendChild(panels[i].cloneNode(true)));
        main.appendChild(grid);
      }
      if (g.footer) main.appendChild(document.querySelector("footer").cloneNode(true));
      main.querySelectorAll("[id]").forEach((e) => e.removeAttribute("id"));
      return { xml: new XMLSerializer().serializeToString(main), text: main.textContent };
    }, g);

    const fonts = fontFaces(body.text);
    for (const dark of [false, true]) {
      const css = fonts + cssFromPage(html, dark);
      const wrap = `<div xmlns="http://www.w3.org/1999/xhtml" class="root" style="width:${WIDTH}px"><style>${css.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</style>${body.xml}</div>`;
      await measure.setContent(`<!doctype html><html><body style="margin:0">${wrap}</body></html>`, { waitUntil: "load" });
      await measure.evaluate(() => document.fonts.ready);
      await measure.addStyleTag({ content: "*{animation:none!important}" });
      const h = Math.ceil(await measure.evaluate(() => document.querySelector(".root").getBoundingClientRect().height));
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${h}" viewBox="0 0 ${WIDTH} ${h}" role="img"><title>${g.alt.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</title><foreignObject x="0" y="0" width="${WIDTH}" height="${h}">${wrap}</foreignObject></svg>\n`;
      const name = `${g.file}_${dark ? "dark" : "light"}.svg`;
      fs.writeFileSync(path.join(OUT, name), svg);
      console.log(name, h + "px", Math.round(svg.length / 1024) + " KB");
    }
  }
  await browser.close();
})();
