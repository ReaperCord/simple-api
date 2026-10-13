'use strict';

// Lint minimo sem dependencias: roda `node --check` (erros de sintaxe) em
// todos os .js de src/, scripts/ e test/.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const dirs = ['src', 'scripts', 'test'];

function listJsFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return listJsFiles(full);
    return entry.name.endsWith('.js') ? [full] : [];
  });
}

const files = dirs.flatMap((d) => listJsFiles(path.join(root, d)));
let failed = 0;
for (const file of files) {
  const result = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' });
  if (result.status !== 0) {
    failed += 1;
    process.stderr.write(`${path.relative(root, file)}\n${result.stderr}\n`);
  }
}

process.stdout.write(`lint: ${files.length} arquivos verificados, ${failed} com erro\n`);
process.exit(failed === 0 ? 0 : 1);
