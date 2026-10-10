import { defineConfig } from 'astro/config';

// CSS is ~5 KB gzipped: inline it so the hero headline is not held back by a stylesheet request.
export default defineConfig({ devToolbar: { enabled: false }, build: { inlineStylesheets: 'always' } });
