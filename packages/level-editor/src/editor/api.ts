// Client for the build API (server/api.ts).

import type { BuildResult, Layout } from '../../server/api.ts';

export type { BuildError, BuildResult } from '../../server/api.ts';

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  let res: Response;
  try {
    res = await fetch(path, {
      method,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    });
  } catch {
    throw new ApiError('the editor server is not running (npm run dev or npm run serve)', 0);
  }
  const data = await res.json().catch(() => ({}));
  if (res.status === 404 && path.startsWith('/api/') && !data.error)
    throw new ApiError('no build API here: run the editor with npm run dev or npm run serve', 404);
  if (!res.ok) throw new ApiError(data.error ?? `HTTP ${res.status}`, res.status, data);
  return data as T;
}

export interface Source {
  name: string;
  levelsAsm: string;
  tablesAsm: string;
  hash: string;
  layout: Layout;
}

export const getSource = () => call<Source>('GET', '/api/source');


export const build = (levelsAsm: string, tablesAsm: string, startLevel: number | null) =>
  call<BuildResult>('POST', '/api/build', { levelsAsm, tablesAsm, startLevel });

export const buildFileUrl = (id: string, file: string) => `/api/builds/${id}/${file}`;

export async function fetchBuildFile(id: string, file: string): Promise<Uint8Array> {
  const res = await fetch(buildFileUrl(id, file));
  if (!res.ok) throw new ApiError(`could not fetch ${file}`, res.status);
  return new Uint8Array(await res.arrayBuffer());
}
