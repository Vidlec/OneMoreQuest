// The product page as GitHub Pages serves it, on this machine: bun run site:preview [port]. Builds it (build.ts),
// then serves dist/site under /OneMoreQuest/, the path the published site has (so a link that would break there
// breaks here too); / goes there. Build again (bun run site) and reload to see a change.
//
// /curseforge/ shows CurseForge's description (dist/site/curseforge-description.html) as a project page would: in a
// column on CurseForge's dark ground, its pictures (the published site's, by full address) taken from here instead
// (its links left as they are).
// An approximation of CurseForge's look, for reading it through before pasting it in.

import { existsSync, readFileSync, statSync } from "node:fs";
import { join, normalize, sep } from "node:path";

const ROOT = join(import.meta.dir, "..", "..");
const SITE = join(ROOT, "dist", "site");
const BASE = "/OneMoreQuest/";
const port = Number(process.argv[2] ?? process.env.PORT ?? 4321);

const built = Bun.spawnSync(["bun", join(import.meta.dir, "build.ts")], {
  stdout: "inherit",
  stderr: "inherit",
});
if (built.exitCode !== 0) {
  process.exit(built.exitCode ?? 1);
}

/** The file a path under the base names (a folder's index.html), or nothing outside dist/site */
const findFile = (pathname: string) => {
  const relative = decodeURIComponent(pathname.slice(BASE.length));
  const path = normalize(join(SITE, relative));
  if (path !== SITE && !path.startsWith(SITE + sep)) {
    return undefined;
  }
  if (existsSync(path) && statSync(path).isDirectory()) {
    const index = join(path, "index.html");
    return existsSync(index) ? index : undefined;
  }
  return existsSync(path) ? path : undefined;
};

const CURSEFORGE_PATH = "/curseforge/";

// CurseForge's project page, near enough: its dark ground, its column, its type; pictures never wider than the column
const composeCurseForgePreview = () => {
  const { url } = JSON.parse(readFileSync(join(ROOT, "site", "site.json"), "utf8")) as { url: string };
  const description = readFileSync(join(SITE, "curseforge-description.html"), "utf8").replaceAll(
    `src="${url}`,
    `src="${BASE}`,
  );
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CurseForge description (preview)</title>
<style>
  body { margin: 0; background: #0d0d0d; color: #e6e6e6; font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; }
  .note { padding: 10px 24px; background: #2b2b2b; color: #bdbdbd; font-size: 14px; }
  .column { max-width: 880px; margin: 0 auto; padding: 32px 24px 64px; background: #1a1a1a; }
  .column h2 { margin: 32px 0 8px; font-size: 22px; color: #fff; }
  .column a { color: #f16436; }
  .column img { max-width: 100%; height: auto; }
  .column code { background: #2b2b2b; padding: 1px 4px; border-radius: 3px; }
</style>
</head>
<body>
<p class="note">CurseForge description, as pasted from dist/site/curseforge-description.html (an approximation of
CurseForge's page; its pictures served from here until the site is published).</p>
<main class="column">
${description}
</main>
</body>
</html>
`;
};

const server = Bun.serve({
  hostname: "127.0.0.1",
  port,
  fetch: (request) => {
    const { pathname } = new URL(request.url);
    if (pathname === CURSEFORGE_PATH || pathname === CURSEFORGE_PATH.slice(0, -1)) {
      return new Response(composeCurseForgePreview(), {
        headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
      });
    }
    if (!pathname.startsWith(BASE)) {
      return Response.redirect(BASE, 302);
    }
    const file = findFile(pathname);
    // (no caching: a build is seen at the next reload)
    return file
      ? new Response(Bun.file(file), { headers: { "Cache-Control": "no-store" } })
      : new Response("Not found", { status: 404 });
  },
});

console.log(`the product page: http://127.0.0.1:${server.port}${BASE}`);
console.log(`CurseForge's description: http://127.0.0.1:${server.port}${CURSEFORGE_PATH}`);
