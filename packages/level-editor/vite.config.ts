import { execFileSync } from 'node:child_process';
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

/** Shown in the panel: the release tag (v0.2.0), or how far past it the build is
 *  (v0.2.0-3-g41c95c1); package.json's version when there is no git or no tag. */
function appVersion(): string {
  const git = (...args: string[]) => execFileSync('git', args, { cwd: import.meta.dirname, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  const pkg = `v${JSON.parse(readFileSync(new URL('package.json', import.meta.url), 'utf8')).version}`;
  try {
    return git('describe', '--tags', '--match', 'v*', '--dirty');
  } catch {
    try {
      return `${pkg}-g${git('rev-parse', '--short', 'HEAD')}`;
    } catch {
      return pkg;
    }
  }
}

export default defineConfig({
  plugins: [editorServer()],
  define: { __APP_VERSION__: JSON.stringify(appVersion()) },
  test: { include: ['test/**/*.test.ts'] },
});
