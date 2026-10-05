// assets.mjs - local raster/vector images (Paper requires paper-asset:/// URLs for local files).
//   asset(relPath, {name, width, height, radius, fit='cover'})   relPath is relative to Design/paper/assets/, e.g. 'thumbs/S-shell-default.png'.
//     Emits <img layer-name data-asset ... src="@asset:<relPath>">. build.mjs rewrites the marker: in the .html it becomes a
//     RELATIVE path from the artboard file to Design/paper/assets/<relPath> (browsers, preview.html); in fragments.json it becomes
//     paper-asset:///<absolute path> and the fragment gets `hasAsset: true`. check.mjs verifies the file exists and allows <img> only here.
//   Prefer inline SVG for icons and logos; use this only for real images (screen thumbnails on flow boards).
import { Html, esc, px } from './h.mjs';
export function asset(relPath, { name, width, height, radius, fit = 'cover' } = {}) {
  if (!name || name.length > 50) throw new Error(`asset(): "name" (layer-name, <= 50 chars) required for ${relPath}`);
  if (relPath.startsWith('/') || relPath.includes('..')) throw new Error(`asset(): path must be relative to Design/paper/assets/: ${relPath}`);
  const st = `box-sizing:border-box;display:block;flex-shrink:0;width:${px(width)};height:${px(height)};object-fit:${fit}${radius !== undefined ? `;border-radius:${px(radius)}` : ''}`;
  return new Html(`<img layer-name="${esc(name)}" data-asset="${esc(relPath)}" src="@asset:${esc(relPath)}" style="${st}">`);
}
