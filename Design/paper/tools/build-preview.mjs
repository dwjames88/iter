#!/usr/bin/env node
// build-preview.mjs - writes Design/paper/preview.html: every artboard from artboards/manifest.json in build-plan order
// (Foundations, Components, Screens light, Screens dark, Flows), each as a scaled iframe of the real artboard file, with name,
// size, link to open full size, and a sticky index. Manifest is read at build time (file:// fetch is blocked).
//   node Design/paper/tools/build-preview.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
import { PAGES as ORDER, orderManifest, groupOf } from './lib/order.mjs';
const man = orderManifest(JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', 'manifest.json'), 'utf8'))); // canonical order: tools/lib/order.mjs
const tokenTable = Object.fromEntries([...fs.readFileSync(path.join(paperDir, 'tokens.css'), 'utf8').matchAll(/^\s*(--[\w-]+):\s*(.+);\s*$/gm)].map((m) => [m[1], m[2]]));
const stemOf = (m) => path.basename(m.file, '.html');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
function groupsOf(items) {
  const out = [];
  for (const m of items) {
    const g = groupOf(m).label;
    const last = out[out.length - 1];
    if (last && last.label === g) last.list.push(m); else out.push({ label: g, list: [m] });
  }
  return out;
}
const pages = ORDER.map((p) => ({ page: p, items: man.filter((m) => m.page === p) })).filter((p) => p.items.length);
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-');
const THUMB = 640; // companion note artboards render at their own scale beside the artboard // max rendered width in px
const sections = pages.map(({ page, items }) => `
<section id="${slug(page)}"><h2>${esc(page)} <span class="n">${items.length}</span></h2>
${groupsOf(items).map(({ label, list }) => `<h3>${esc(label)} <span class="n">${list.filter((x) => !x.companionOf).length}</span></h3><div class="grid">${list.filter((m) => !m.companionOf).map((m) => {
    const comp = items.find((x) => x.companionOf === m.id && x.theme === m.theme);
    const one = (m, cls, forced) => {
    const sc = forced ?? Math.min(1, THUMB / m.width);
    const w = Math.round(m.width * sc), h = Math.round(m.height * sc);
    return `<figure${cls ? ` class="${cls}"` : ''} id="${esc(m.id + '-' + m.theme)}"><figcaption><a class="name" href="artboards/${esc(m.file)}" target="_blank">${esc(m.name)}</a><span class="meta">${m.width}×${m.height} · ${esc(m.theme)} · ${(m.bytes / 1024).toFixed(0)} KB</span><span class="btns"><button data-stem="${esc(stemOf(m))}" data-mode="tokens">Copy for Paper</button><button data-stem="${esc(stemOf(m))}" data-mode="literal">Copy literal</button></span></figcaption>
<div class="frame" style="width:${w}px;height:${h}px"><iframe loading="lazy" src="artboards/${esc(m.file)}" title="${esc(m.name)}" scrolling="no" style="width:${m.width}px;height:${m.height}px;transform:scale(${sc.toFixed(4)})"></iframe></div></figure>`;
    };
    return comp ? `<div class="pair">${one(m)}${one(comp, 'note', Math.min(1, THUMB / m.width))}</div>` : one(m);
  }).join('')}</div>`).join('')}</section>`).join('\n');
const index = pages.map(({ page, items }) => `<div class="grp"><a class="gh" href="#${slug(page)}">${esc(page)}</a>${items.map((m) => `<a href="#${esc(m.id + '-' + m.theme)}">${esc(m.name)}</a>`).join('')}</div>`).join('');
fs.writeFileSync(path.join(paperDir, 'preview.html'), `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Iter artboards preview</title>
<link rel="stylesheet" href="tokens.css">
<style>
body{margin:0;font:13px/16px var(--font-sans);background:var(--color-canvas-artboard);color:var(--color-canvas-label-title);display:flex}
nav{position:sticky;top:0;align-self:flex-start;width:240px;height:100vh;overflow:auto;flex-shrink:0;padding:16px;box-sizing:border-box;border-right:1px solid var(--color-canvas-specimen-border);background:var(--color-canvas-specimen-background)}
nav a{display:block;color:var(--color-canvas-label-body);text-decoration:none;padding:2px 0;font-size:12px}
nav a:hover{color:var(--color-canvas-label-title)} nav .gh{font-weight:600;color:var(--color-canvas-label-title);margin-top:12px}
main{padding:24px 32px;min-width:0;flex:1}
h1{font-size:22px;line-height:28px;margin:0 0 4px} h2{font-size:17px;margin:32px 0 12px;scroll-margin-top:12px} h3{font-size:14px;margin:24px 0 10px;color:var(--color-canvas-label-body)} .n{color:var(--color-canvas-label-body);font-weight:400}
.sub{color:var(--color-canvas-label-body)}
.pair{display:flex;gap:16px;align-items:flex-start}
.grid{display:flex;flex-wrap:wrap;gap:24px;align-items:flex-start}
figure{margin:0;scroll-margin-top:12px} figcaption{display:flex;flex-direction:column;gap:2px;margin-bottom:6px}
.name{font-weight:600;color:var(--color-canvas-label-title);text-decoration:none} .name:hover{text-decoration:underline}
.btns{display:flex;gap:6px;margin-top:2px} button{font:11px/14px var(--font-sans);padding:2px 8px;border-radius:999px;border:1px solid var(--color-canvas-specimen-border);background:var(--color-canvas-specimen-background);color:var(--color-canvas-label-title);cursor:pointer} button.ok{background:var(--color-canvas-note-background);border-color:var(--color-canvas-note-border)}
.meta{font-size:11px;color:var(--color-canvas-label-body)}
.frame{position:relative;overflow:hidden;border:1px solid var(--color-canvas-specimen-border);box-sizing:content-box;background:var(--color-canvas-specimen-background)}
iframe{border:0;transform-origin:0 0;display:block}
</style></head><body>
<nav><strong>Artboards</strong>${index}</nav>
<main><h1>Iter → Paper artboards</h1><div class="sub">${man.length} artboards. Generated by tools/build-preview.mjs. Click a name to open an artboard at full size. <b>Copy for Paper</b> copies the artboard's root element (data-artboard) with var(--token) references intact; <b>Copy literal</b> resolves every var() to its value. Paste with \u2318V into Paper. Run <code>node tools/paste-bundle.mjs</code> first (the buttons load <code>paste/js/*.js</code>). Flow thumbnails are copied as <code>paper-asset:///</code> paths; Paper's paste docs say pasted images need public URLs, so they may not come through: drag the PNGs from <code>Design/paper/assets/thumbs/</code> onto the canvas instead.</div>
${sections}</main>
<script>
var TOKENS=${JSON.stringify(tokenTable)};
function resolveVars(v,d){d=d||0;return v.replace(/var\\((--[\\w-]+)\\)/g,function(_,n){if(!(n in TOKENS)||d>8)throw new Error('unknown '+n);return resolveVars(TOKENS[n],d+1).replace(/"/g,"'");});}
function copyText(t){return (navigator.clipboard&&navigator.clipboard.writeText?navigator.clipboard.writeText(t):Promise.reject()).catch(function(){var a=document.createElement('textarea');a.value=t;a.style.position='fixed';a.style.opacity='0';document.body.appendChild(a);a.select();var ok=document.execCommand('copy');document.body.removeChild(a);if(!ok)throw new Error('copy failed');});}
function loadStem(stem){return new Promise(function(res,rej){if(window.__PASTE&&window.__PASTE[stem])return res(window.__PASTE[stem]);var s=document.createElement('script');s.src='paste/js/'+stem+'.js';s.onload=function(){res(window.__PASTE[stem])};s.onerror=function(){rej(new Error('paste/js/'+stem+'.js missing: run tools/paste-bundle.mjs'))};document.head.appendChild(s);});}
document.addEventListener('click',function(e){var b=e.target.closest('button[data-stem]');if(!b)return;var label=b.textContent;loadStem(b.dataset.stem).then(function(h){return copyText(b.dataset.mode==='literal'?resolveVars(h):h)}).then(function(){b.textContent='Copied';b.classList.add('ok');setTimeout(function(){b.textContent=label;b.classList.remove('ok')},1500)}).catch(function(err){b.textContent='Failed';b.title=String(err&&err.message||err);setTimeout(function(){b.textContent=label},2500)});});
</script></body></html>
`);
console.log(`preview.html: ${man.length} artboards in ${pages.length} pages`);
