import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const docsDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoDir = resolve(docsDir, '..');
const contentDir = join(docsDir, 'src', 'content', 'docs');
const publicDir = join(docsDir, 'public');
const rootDocs = ['README.md', 'AGENTS.md', 'SKILL.md'].map((name) => join(repoDir, name));

function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return walk(path);
    return /\.mdx?$/.test(entry.name) ? [path] : [];
  });
}

function localCandidates(source, rawTarget) {
  const target = decodeURIComponent(rawTarget.split('#', 1)[0].split('?', 1)[0]);
  if (!target) return [];

  let base;
  if (target.startsWith('/')) {
    const route = target.replace(/^\/+|\/+$/g, '');
    if (route.startsWith('images/')) return [join(publicDir, route)];
    base = route ? join(contentDir, route) : join(contentDir, 'index');
  } else {
    base = resolve(dirname(source), target);
  }

  if (extname(base)) return [base];
  return [base, `${base}.md`, `${base}.mdx`, join(base, 'index.md'), join(base, 'index.mdx')];
}

function targets(source, text) {
  const found = [];
  const markdownLink = /!?\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g;
  const href = /\bhref=["']([^"']+)["']/g;
  for (const pattern of [markdownLink, href]) {
    for (const match of text.matchAll(pattern)) found.push(match[1].replace(/^<|>$/g, ''));
  }
  return found;
}

const failures = [];
for (const file of [...rootDocs, ...walk(contentDir)]) {
  const text = readFileSync(file, 'utf8');
  for (const target of targets(file, text)) {
    if (!target || target.startsWith('#') || target.startsWith('{')) continue;
    if (/^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith('//')) continue;
    const candidates = localCandidates(file, target);
    if (candidates.length > 0 && !candidates.some(existsSync)) {
      failures.push(`${file.slice(repoDir.length + 1).split(sep).join('/')}: ${target}`);
    }
  }
}

if (failures.length) {
  console.error('Broken local documentation links:');
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`Link check passed (${rootDocs.length + walk(contentDir).length} files).`);
