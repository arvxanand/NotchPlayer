// Runs after `astro build`: reads dist/ and src/, applies tools/check-lib.mjs.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check } from './check-lib.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const html = readFileSync(join(dist, 'index.html'), 'utf8');
const inline = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1]).join('\n'); // CSS is inlined (astro.config.mjs)
const cssDir = join(dist, '_astro');
const css = inline + (existsSync(cssDir) ? readdirSync(cssDir).filter((f) => f.endsWith('.css')).map((f) => readFileSync(join(cssDir, f), 'utf8')).join('\n') : '');

const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]));
const src = walk(join(root, 'src')).filter((f) => /\.(ts|astro|css|json)$/.test(f)).map((f) => ({ file: relative(root, f), text: readFileSync(f, 'utf8') }));
const dmgUrl = readFileSync(join(root, 'src/config.ts'), 'utf8').match(/dmgUrl:\s*'([^']+)'/)?.[1] ?? '';

const { fail, words } = check({ html, css, src, dmgUrl });
console.log(`check-static: ${words} words`);
if (fail.length) { console.error(fail.join('\n')); process.exit(1); }
