import { existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
export async function resolve(spec, ctx, next) {
  if ((spec.startsWith('./') || spec.startsWith('../')) && ctx.parentURL && !/\.[a-z]+$/.test(spec)) {
    const base = path.resolve(path.dirname(fileURLToPath(ctx.parentURL)), spec);
    for (const ext of ['.ts', '/index.ts']) if (existsSync(base + ext)) return next(pathToFileURL(base + ext).href, ctx);
  }
  return next(spec, ctx);
}
