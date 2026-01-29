// Build script to bundle beautiful-mermaid for browser usage
import { build } from 'esbuild';

await build({
  stdin: {
    contents: `
      import { renderMermaid, THEMES, DEFAULTS } from 'beautiful-mermaid';
      window.beautifulMermaid = { renderMermaid, THEMES, DEFAULTS };
    `,
    resolveDir: '.',
    loader: 'js',
  },
  bundle: true,
  format: 'iife',
  outfile: 'ui/beautiful-mermaid.min.js',
  minify: true,
  sourcemap: false,
  target: ['es2020'],
  platform: 'browser',
});

console.log('Built ui/beautiful-mermaid.min.js');
