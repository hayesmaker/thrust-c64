// pm2 app for the level editor on the server (deploy/update.sh starts or reloads it).
// No secrets here: this file is public.
const path = require('node:path');

module.exports = {
  apps: [
    {
      name: 'thrust-level-editor',
      cwd: path.join(__dirname, '../packages/level-editor'),
      script: 'server/index.ts',
      // Node 22.18+ runs .ts itself. update.sh sets THRUST_NODE to the editor's own
      // Node (packages/level-editor/.node-version), so other pm2 apps keep theirs.
      interpreter: process.env.THRUST_NODE || 'node',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '400M',
      env: {
        NODE_ENV: 'production',
        HOST: '127.0.0.1', // nginx proxies /api/ to here
        PORT: 5180,
        KICKASS: '/opt/KickAss.jar',
        KICKASS_JAVA: path.join(__dirname, 'kickass-sandbox.sh'),
        BUILD_TIMEOUT_MS: 30000,
        BUILD_MAX_QUEUE: 8,
      },
    },
  ],
};
