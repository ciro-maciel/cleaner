#!/usr/bin/env bun
// Regenerates everything in Resources/ that comes from outside this folder:
//   - Montserrat (OFL, from its upstream repository), the only interface family
//   - Tabler icons (MIT), outline, stroke 1.5, as template PDFs
//   - the app icon: the letter C, through the public favicon tool at ciromaciel.click/tools
//     (Candal, 555555 on white, size 60)
//
// Resources/ is committed, so a build never needs this script.
//
//   bun scripts/assets.mjs
//
// Needs rsvg-convert (brew install librsvg), sips and iconutil (both ship with macOS).

import { $ } from 'bun';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const RES = join(ROOT, 'Resources');

// --- fonts -----------------------------------------------------------------
const FONT_WEIGHTS = ['Regular', 'Medium', 'Bold', 'ExtraBold', 'Black'];
mkdirSync(join(RES, 'Fonts'), { recursive: true });
for (const w of FONT_WEIGHTS) {
  const file = `Montserrat-${w}.ttf`;
  const url = `https://github.com/JulietaUla/Montserrat/raw/master/fonts/ttf/${file}`;
  writeFileSync(join(RES, 'Fonts', file), Buffer.from(await (await fetch(url)).arrayBuffer()));
}
console.log(`fonts: ${FONT_WEIGHTS.length}`);

// --- Tabler icons ------------------------------------------------------------
const ICONS = [
  'layout-dashboard', 'sparkles', 'package', 'chart-treemap', 'rocket', 'shield-check',
  'scan', 'refresh', 'folder', 'folder-open', 'file', 'trash', 'arrow-back-up', 'external-link',
  'alert-circle', 'alert-triangle', 'check', 'lock', 'x', 'chevron-right', 'chevron-down',
  'arrow-left', 'info-circle', 'search', 'square', 'square-check', 'square-minus', 'power',
  'player-stop', 'clock', 'home', 'device-desktop', 'eye', 'settings', 'apps',
  // Monitor
  'activity', 'cpu', 'gauge', 'stack-2', 'device-sd-card', 'arrows-down-up', 'arrow-down', 'arrow-up',
  'battery', 'battery-charging', 'temperature', 'clock-hour-4', 'app-window', 'bolt',
];
mkdirSync(join(RES, 'Icons'), { recursive: true });
const tmp = join(tmpdir(), 'cleaner-assets');
mkdirSync(tmp, { recursive: true });
for (const name of ICONS) {
  let svg = await (await fetch(`https://unpkg.com/@tabler/icons@3.19.0/icons/outline/${name}.svg`)).text();
  // Our standard: stroke 1.5; black so the PDF works as a template image.
  svg = svg.replace('stroke-width="2"', 'stroke-width="1.5"').replace('stroke="currentColor"', 'stroke="#000000"');
  const src = join(tmp, `${name}.svg`);
  writeFileSync(src, svg);
  await $`rsvg-convert -f pdf -o ${join(RES, 'Icons', `${name}.pdf`)} ${src}`.quiet();
}
console.log(`icons: ${ICONS.length}`);

// --- illustrations ------------------------------------------------------------
// None in this repository: the ones in the official build came from a licensed stock
// gallery that can't be redistributed. Without them, each screen draws the Tabler icon of
// the same idea (Illustration in Sources/Cleaner/UI/Theme.swift). To use your own, drop
// 560 × 560 PNGs named scan, cleanup, uninstall, diskmap, startup, quarantine, done and
// access into Resources/Illustrations.

// --- app icon ------------------------------------------------------------------
const res = await fetch('https://mcp.tools.ciromaciel.click', {
  method: 'POST',
  headers: { 'User-Agent': 'curl/8.7.1', 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
  body: JSON.stringify({
    jsonrpc: '2.0', id: 1, method: 'tools/call',
    params: { name: 'generate_favicon', arguments: { mode: 'text', text: 'C', font: 'Candal', background: 'ffffff', color: '555555', size: 60, adaptive: false } },
  }),
});
let raw = await res.text();
if (raw.startsWith('event:') || raw.startsWith('data:')) raw = raw.split('\n').find(l => l.startsWith('data:')).slice(5);
const result = JSON.parse(raw).result;
if (result.isError) throw new Error(`favicon tool: ${result.content?.[0]?.text}`);
const out = result.structuredContent ?? JSON.parse(result.content[0].text);
const iconSvg = join(tmp, 'icon.svg');
writeFileSync(iconSvg, out.svg);
const iconset = join(tmp, 'AppIcon.iconset');
rmSync(iconset, { recursive: true, force: true });
mkdirSync(iconset);
const master = join(tmp, 'icon-1024.png');
await $`rsvg-convert -w 1024 -h 1024 -o ${master} ${iconSvg}`.quiet();
for (const size of [16, 32, 128, 256, 512]) {
  await $`sips -z ${size} ${size} ${master} --out ${join(iconset, `icon_${size}x${size}.png`)}`.quiet();
  await $`sips -z ${size * 2} ${size * 2} ${master} --out ${join(iconset, `icon_${size}x${size}@2x.png`)}`.quiet();
}
await $`iconutil -c icns -o ${join(RES, 'AppIcon.icns')} ${iconset}`.quiet();
console.log(`app icon: C → ${out.link ?? 'ok'}`);
