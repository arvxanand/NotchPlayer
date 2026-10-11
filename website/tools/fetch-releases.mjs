// Writes src/data/releases.json: the published GitHub releases, notes already rendered to HTML.
// Run by hand after publishing a release (`npm run releases`), then commit. The build never
// touches the network, so a GitHub outage or rate limit can't break a deploy.
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = 'arvxanand/NotchPlayer';
const headers = { Accept: 'application/vnd.github+json', ...(process.env.GITHUB_TOKEN && { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` }) };
const get = async (url, init) => {
  const res = await fetch(url, init);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  return res;
};

const list = await (await get(`https://api.github.com/repos/${repo}/releases?per_page=30`, { headers })).json();
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Notes written by hand go through GitHub's own markdown renderer, so the page carries no parser.
// GitHub's auto-generated "What's Changed" lists ("fix x by @someone in <url>") are kept to the
// plain sentence plus the compare link.
const render = async (text) => {
  if (!text.trim()) return '';
  if (!text.startsWith("## What's Changed")) return (await get('https://api.github.com/markdown', { method: 'POST', headers, body: JSON.stringify({ text: text.replace(/^## .*\n+/, ''), mode: 'gfm', context: repo }) })).text();
  const items = [...text.matchAll(/^\* (.+?) by @\S+ in \S+$/gm)].map((m) => `<li>${esc(m[1])}</li>`);
  const compare = text.match(/\*\*Full Changelog\*\*: (\S+)/)?.[1];
  return `<ul>${items.join('')}</ul>` + (compare ? `<p><a href="${compare}">Full changelog on GitHub</a></p>` : '');
};
const releases = [];
for (const r of list) {
  if (r.draft || r.prerelease) continue;
  const text = (r.body ?? '').replace(/\r/g, '').replace(/\s—\s|—/g, ', '); // the site's copy rules ban em dashes
  releases.push({ version: r.tag_name.replace(/^v/, ''), date: r.published_at.slice(0, 10), html: await render(text) });
}
const out = join(dirname(fileURLToPath(import.meta.url)), '../src/data/releases.json');
writeFileSync(out, JSON.stringify(releases, null, 2) + '\n');
console.log(`releases: wrote ${releases.length} to src/data/releases.json`);
