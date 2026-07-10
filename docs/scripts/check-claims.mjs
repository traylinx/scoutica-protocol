import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const docsDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoDir = resolve(docsDir, '..');
const contentDir = join(docsDir, 'src', 'content', 'docs');
const rootDocs = ['README.md', 'AGENTS.md', 'SKILL.md'].map((name) => join(repoDir, name));

function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return walk(path);
    return /\.mdx?$/.test(entry.name) ? [path] : [];
  });
}

const forbidden = [
  ['obsolete docs-site path', /\bdocs-site(?:\/|\b)/i],
  ['obsolete documentation platform', /\bMintlify\b/i],
  ['obsolete documentation config', /\bdocs\.json\b/i],
  ['obsolete documentation command', /\bmint (?:dev|broken-links)\b/i],
];

const scanClaimFiles = new Set([
  join(repoDir, 'README.md'),
  join(repoDir, 'SKILL.md'),
  join(contentDir, 'index.mdx'),
  join(contentDir, 'introduction.mdx'),
  join(contentDir, 'installation.mdx'),
  join(contentDir, 'architecture', 'overview.mdx'),
  join(contentDir, 'cli', 'overview.mdx'),
  join(contentDir, 'cli', 'scan.mdx'),
  join(contentDir, 'guides', 'create-card.mdx'),
  join(contentDir, 'guides', 'privacy-zones.mdx'),
  join(contentDir, 'skill-card', 'profile.mdx'),
]);

const forbiddenScanClaims = [
  ['categorical scan locality claim', /\b(?:your )?(?:documents(?: and data)?|data) never leave your machine\b/i],
  ['categorical scan locality claim', /\bdocuments processed by `?scoutica scan`? never leave\b/i],
  ['categorical scan locality claim', /\bnothing leaves (?:your|their) machine unless (?:you|they) publish\b/i],
  ['categorical scan locality claim', /\bno data leaves your machine\b/i],
  ['categorical scan locality claim', /\bno data leaving your machine\b/i],
  ['categorical scan locality claim', /\ball AI processing runs locally\b/i],
  ['categorical scan locality claim', /\bscan is local\b/i],
  ['categorical scan locality claim', /\beverything runs through your local AI CLI\b/i],
  ['categorical scan locality claim', /\bwith no cloud API calls\b/i],
];

const disclosureFiles = new Map([
  [join(repoDir, 'README.md'), /remote service/i],
  [join(repoDir, 'SKILL.md'), /remote-capable AI provider/i],
  [join(contentDir, 'installation.mdx'), /remote-capable AI provider/i],
  [join(contentDir, 'cli', 'scan.mdx'), /remote-capable provider/i],
  [join(contentDir, 'guides', 'privacy-zones.mdx'), /remote-capable provider/i],
]);

const failures = [];
const files = [...rootDocs, ...walk(contentDir)];
for (const file of files) {
  const text = readFileSync(file, 'utf8');
  for (const [label, pattern] of forbidden) {
    const match = pattern.exec(text);
    if (!match) continue;
    const line = text.slice(0, match.index).split('\n').length;
    failures.push(`${relative(repoDir, file).split(sep).join('/')}:${line}: ${label}`);
  }
  if (scanClaimFiles.has(file)) {
    for (const [label, pattern] of forbiddenScanClaims) {
      const match = pattern.exec(text);
      if (!match) continue;
      const line = text.slice(0, match.index).split('\n').length;
      failures.push(`${relative(repoDir, file).split(sep).join('/')}:${line}: ${label}`);
    }
  }
}

for (const [file, pattern] of disclosureFiles) {
  if (!pattern.test(readFileSync(file, 'utf8'))) {
    failures.push(`${relative(repoDir, file).split(sep).join('/')}: missing remote-provider disclosure`);
  }
}

if (failures.length) {
  console.error('Documentation claim check failed:');
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`Claim check passed (${files.length} active files; historical .specs excluded).`);
