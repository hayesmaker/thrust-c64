import { readFileSync } from 'node:fs';
import { type Plugin } from 'vite';
import { defineConfig } from 'vitest/config';
import { createApi } from './server/api.ts';
import { C64_ASSETS, MOD_SRC, TEMPLATE } from './server/paths.ts';

/** Dev server: the build API (server/api.ts) and c64-ready's runtime files
 *  under /c64/. The production build copies the c64-ready files into dist/c64/. */
function editorServer(): Plugin {
  return {
    name: 'thrust-editor-server',
    configureServer(server) {
      server.middlewares.use(createApi({ modDir: MOD_SRC, template: TEMPLATE }));
      server.middlewares.use('/c64', (req, res, next) => {
        const a = C64_ASSETS[(req.url ?? '').replace(/^\/|\?.*$/g, '')];
        if (!a) return next();
        res.setHeader('Content-Type', a.type);
        res.end(readFileSync(a.path));
      });
    },
    generateBundle() {
      for (const [name, a] of Object.entries(C64_ASSETS))
        this.emitFile({ type: 'asset', fileName: `c64/${name}`, source: readFileSync(a.path) });
    },
  };
}

export default defineConfig({
  plugins: [editorServer()],
  test: { include: ['test/**/*.test.ts'] },
});
