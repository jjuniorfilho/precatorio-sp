#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');

// ─── Constants ───────────────────────────────────────────────────────────────

const VERSION = require('../package.json').version;
const PACKAGE_CLAUDE_DIR = path.join(__dirname, '..', '.claude');
const TARGET_DIR = process.cwd();
const TARGET_CLAUDE_DIR = path.join(TARGET_DIR, '.claude');
const SESSIONS_DIR = path.join(TARGET_CLAUDE_DIR, 'sessions');

const EXCLUDE_PATTERNS = ['settings.local.json'];

// ─── Node Version Guard ─────────────────────────────────────────────────────

const [major] = process.versions.node.split('.').map(Number);
if (major < 18) {
  console.error('\n  Cortex CDD requer Node.js 18 ou superior.');
  console.error(`  Versao atual: ${process.version}\n`);
  process.exit(1);
}

// ─── ANSI Colors ─────────────────────────────────────────────────────────────

const c = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  magenta: '\x1b[35m',
};

// ─── UI Helpers ──────────────────────────────────────────────────────────────

function printBanner() {
  const brain = [
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⠤⠤⠤⠤⣄⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣶⡊⠉⠉⣉⣱⡷⠶⢢⣠⢴⣶⡝⠒⠉⢉⣭⡽⠟⢉⣀⡀⠹⢭⠒⢤⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡠⠔⢚⣩⡽⠿⠊⢉⣉⡂⣀⣩⠭⢴⠟⠋⠉⠉⠉⠛⠳⢦⣬⣤⡴⠞⠛⠁⠛⠳⣾⣧⠀⠟⠀⠉⠲⢄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⢚⠁⠀⠰⠋⢡⠄⠀⠞⣫⢟⡥⠒⠉⠹⣿⡀⠀⠀⢦⡀⠀⠀⠀⠈⠻⡧⡀⠀⠀⠀⠀⠈⠻⣗⡶⠶⠶⢤⡀⠱⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢮⣤⡾⠀⠀⣠⡴⠋⠀⡠⣚⠥⠒⢛⡲⠄⠀⠈⢻⡆⠀⠀⠻⣦⣀⠀⠀⠀⣿⠻⣦⣀⣴⠶⠂⠀⠘⣷⡄⠀⠀⢀⣴⡿⠈⠢⡀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⡠⠖⣉⣁⡀⠀⢀⣾⠋⠴⢿⣽⠋⠀⠞⢉⣉⣽⣳⣄⣀⠀⠋⠀⠀⠀⠈⠙⣷⡄⠀⠁⠀⠙⢤⣯⡀⠀⠀⠀⣼⡇⠀⡾⠋⠁⠀⠳⣄⠘⢆⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⡰⠋⠰⠛⢻⡞⢉⣠⣼⡇⢀⣴⠟⠛⠒⣴⠟⠋⠉⠀⠀⢀⣀⣀⡀⠀⠀⠀⠀⠀⣸⡇⠀⠀⠳⣄⠀⠉⢿⣄⠀⢰⣿⣧⡀⠀⣴⠶⠶⣦⡼⢧⠈⢣⠀⠀⠀⠀',
    '⠀⠀⠀⢀⡞⣡⣶⡄⠀⡟⣳⠿⠋⠙⡍⡽⠁⣀⣤⣤⣿⡄⠀⠀⠀⠀⡿⡉⣀⣀⣤⣤⣤⣴⠾⠥⠽⣦⣄⠀⠉⠻⢶⡼⢻⠀⠈⠇⠘⡷⡄⠘⠂⠀⢀⡍⠻⣷⣄⡇⠀⠀⠀',
    '⠀⠀⠀⠘⣺⠏⢸⢃⣼⠟⢁⡤⠀⣠⢟⡷⠟⢋⣉⣤⡿⠇⠀⠀⠀⢰⣣⠞⠋⠉⠉⠁⡀⠀⠀⠀⠀⠀⠙⢷⣄⠀⠀⢹⣾⠀⠀⠀⠀⢸⡇⠀⣀⡀⣾⠀⠀⠈⢻⡁⢦⠀⠀',
    '⠀⠀⣠⢚⣵⣄⠈⣼⡇⠀⢸⠧⢞⡵⠋⠠⠚⠉⠉⠀⠀⢀⡇⠀⣰⣟⣁⣀⠀⠀⠀⠀⠉⠒⠶⣤⣤⣀⠀⠀⠙⠀⠀⢸⡇⢰⣟⠛⢶⡋⣇⠀⠉⠻⡟⡄⠀⢀⢀⣿⠀⢧⠀',
    '⠀⣰⠃⢸⠁⣿⠀⠸⣧⠀⢸⢣⠋⠀⣠⣤⠶⢶⢒⣤⣔⣻⠣⢼⠟⠁⠀⠙⢷⡄⠀⠀⢀⠀⠀⠀⠈⠓⢟⢦⠀⠀⠀⢸⡇⠈⠻⣦⡀⠈⠻⣷⣄⠀⠘⣿⠀⠸⣿⣇⣀⢸⠀',
    '⠀⡇⠀⠀⣼⠇⠀⢀⣿⠀⣇⣇⣴⠟⠋⢠⣾⠟⠉⠀⠀⠈⠳⣼⠀⠀⠀⠀⠀⠳⠀⠀⠈⢳⣄⠀⠀⠀⢸⣼⠀⠀⠀⠈⡟⢆⠀⠈⢻⡀⠀⠈⢻⣆⠀⣻⠃⠀⠀⢹⡟⠻⡀',
    '⠀⢧⡆⣼⠏⠀⣾⠟⠁⢰⠃⡵⠃⢀⣴⡿⠁⠀⡀⠀⠀⠀⠀⠹⣧⡀⠰⣦⡀⠀⠀⠀⠀⠀⣻⢦⣀⣠⡾⣇⠀⠀⢀⣰⠟⠙⢷⣄⠀⠀⠀⠀⠀⣿⠀⠉⢠⠄⠀⣼⡇⠀⢧',
    '⢀⠞⢡⡟⠀⠀⣿⠀⢀⡏⡼⠁⣴⠟⠁⠀⠀⠀⣿⠀⣀⣀⢀⣴⠘⣷⡀⠈⢻⣦⣀⠀⢀⣾⠟⠉⠀⠀⠉⠻⣷⣄⠀⠀⠀⠀⠀⠙⢷⡄⠀⠀⠀⠉⠀⣠⡟⠀⣼⣟⠀⠀⢸',
    '⢸⠀⠘⣧⠀⡴⠛⠳⢸⢰⠁⢰⠏⠀⠀⠀⢀⣼⡯⠟⠋⠙⠻⣷⡀⠘⠀⠀⠀⠈⠉⠻⣿⠁⠀⠀⢰⡟⠉⠀⠈⢻⣦⠀⠀⠀⣄⠀⠀⡗⠀⢸⡇⣠⣾⠟⢀⣾⠋⠹⣷⢀⡇',
    '⠈⢆⠀⠹⢷⣤⣀⣠⠎⡇⠀⠸⠀⠀⢀⣴⠟⠉⠀⠀⠀⢄⠀⠹⣧⡀⠀⠀⣀⡀⠀⠀⣿⠀⠀⠀⠘⣿⡄⠀⠀⠀⢹⣦⡀⠀⢿⣄⠀⢀⣠⡿⠽⣯⡁⠀⠸⠃⠀⠀⡏⠉⠀',
    '⠀⢠⢷⣄⠀⠈⣉⣉⢢⢳⡀⠀⠀⠀⣾⡏⠀⠀⠠⣀⡤⢿⠀⠀⠙⠷⠶⠛⠉⠈⠀⣰⠟⠀⠀⠀⠀⠘⣷⡀⠀⠠⠛⠉⠉⠀⢈⣯⠗⠛⠁⠀⠀⠈⠃⠀⢀⣴⠇⢠⠇⠀⠀',
    '⠀⢸⡀⠻⣧⠈⠉⠹⣏⢀⣑⠤⣀⣀⠼⠳⣄⠀⠀⠀⠙⠺⠖⣦⣤⠤⣀⡀⠀⠀⠘⠁⠀⠀⠀⠀⠀⠀⢸⢧⡀⠀⠀⢀⣀⢴⣿⣅⡀⠠⠶⢿⢦⣀⣠⣴⠟⠃⡠⠋⠀⠀⠀',
    '⠀⠀⠳⡀⠘⠃⠀⡤⠸⣼⠀⠉⠛⠋⠉⠉⠙⠻⣦⣄⠀⠀⠀⠀⠈⠉⠙⠻⣦⠀⠀⠀⠀⡀⠀⠀⠀⢀⣾⠖⠚⠛⠛⠛⠋⠁⠀⠙⣷⠀⠀⣸⡴⠛⠉⢁⡤⠊⠁⠀⠀⠀⠀',
    '⠀⠀⠀⠘⢦⡀⠸⣧⠀⢻⢇⠀⠳⡤⣤⠆⠀⠀⠈⢻⡇⠀⠀⠀⢰⡄⠀⠀⣿⡇⢀⡾⠛⠛⠻⡝⣲⠟⠋⠀⢀⡄⠀⠀⠀⣀⡄⠀⠋⢀⡴⣻⡄⣤⡶⡍⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠈⠙⠁⠉⠉⠈⠣⡀⠹⣇⠀⠀⠀⠀⠘⠀⠀⠀⢀⡾⢳⡶⠾⠋⠀⠈⠃⠀⠀⣠⠟⢄⣀⣠⡴⠋⠀⠀⠀⣼⢻⣤⣴⠶⠟⠋⣡⡷⣏⢿⡧⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠓⢫⣲⣤⣀⣀⣀⣀⣤⣶⣻⠋⠛⠷⣦⣤⣤⣄⡤⢤⣺⠕⠋⠉⠉⠁⠀⠀⣀⣤⣾⠏⢩⠀⠀⢀⣤⣾⠛⣧⢻⣼⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠓⠮⢭⣉⣉⡩⠥⠚⠈⢇⠀⢠⡄⠀⠉⠉⠙⣿⠀⢠⠶⠖⢫⣩⠟⠛⠛⠉⠀⣠⣿⣦⠶⠿⣭⣸⣇⡿⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠳⣌⡿⣄⠀⠒⠚⠋⠀⠀⠀⣠⡾⠃⠀⢀⣀⠴⠚⠉⠣⢍⣛⣶⡶⠝⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
    '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠒⠂⠀⠒⠒⠉⠀⠉⠉⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀',
  ];

  console.log('');
  brain.forEach(line => console.log(`  ${c.magenta}${line}${c.reset}`));
  console.log('');
  console.log(`  ${c.cyan}${c.bold}  ██████╗ ██████╗ ██████╗ ████████╗███████╗██╗  ██╗${c.reset}`);
  console.log(`  ${c.cyan}${c.bold} ██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝╚██╗██╔╝${c.reset}`);
  console.log(`  ${c.cyan}${c.bold} ██║     ██║   ██║██████╔╝   ██║   █████╗   ╚███╔╝${c.reset}`);
  console.log(`  ${c.cyan}${c.bold} ██║     ██║   ██║██╔══██╗   ██║   ██╔══╝   ██╔██╗${c.reset}`);
  console.log(`  ${c.cyan}${c.bold} ╚██████╗╚██████╔╝██║  ██║   ██║   ███████╗██╔╝ ██╗${c.reset}`);
  console.log(`  ${c.cyan}${c.bold}  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝${c.reset}`);
  console.log(`                ${c.dim}Context-Driven Development ${c.reset}${c.cyan}v${VERSION}${c.reset}`);
  console.log('');
}

function printSuccess(msg) {
  console.log(`  ${c.green}✔${c.reset} ${msg}`);
}

function printWarning(msg) {
  console.log(`  ${c.yellow}⚠${c.reset} ${msg}`);
}

function printError(msg) {
  console.error(`  ${c.red}✖${c.reset} ${msg}`);
}

function printInfo(msg) {
  console.log(`  ${c.cyan}→${c.reset} ${msg}`);
}

function printMenu() {
  console.log(`  ${c.bold}Selecione uma opcao:${c.reset}`);
  console.log('');
  console.log(`  ${c.cyan}[1]${c.reset} Iniciar um novo projeto do zero`);
  console.log(`      ${c.dim}(Copia a pasta .claude/ completa para o diretorio atual)${c.reset}`);
  console.log('');
  console.log(`  ${c.cyan}[2]${c.reset} Atualizar o framework Cortex`);
  console.log(`      ${c.dim}(Atualiza os arquivos preservando sua pasta sessions/)${c.reset}`);
  console.log('');
  console.log(`  ${c.cyan}[0]${c.reset} Cancelar`);
  console.log('');
}

function printNextSteps() {
  console.log('');
  console.log(`  ${c.bold}Proximos passos:${c.reset}`);
  console.log(`  ${c.dim}1. Abra seu projeto com Claude Code, Windsurf ou Cursor${c.reset}`);
  console.log(`  ${c.dim}2. Use /engineer:warm-up para aquecer o contexto${c.reset}`);
  console.log(`  ${c.dim}3. Use /product:warm-up para projetos de produto${c.reset}`);
  console.log('');
}

function printHelp() {
  printBanner();
  console.log(`  ${c.bold}Uso:${c.reset} npx cortex-cdd [opcoes]`);
  console.log('');
  console.log(`  ${c.bold}Opcoes:${c.reset}`);
  console.log(`    ${c.cyan}--new, -n${c.reset}       Iniciar novo projeto (pula menu)`);
  console.log(`    ${c.cyan}--update, -u${c.reset}    Atualizar framework existente (pula menu)`);
  console.log(`    ${c.cyan}--force, -f${c.reset}     Pular confirmacoes`);
  console.log(`    ${c.cyan}--version, -v${c.reset}   Mostrar versao`);
  console.log(`    ${c.cyan}--help, -h${c.reset}      Mostrar esta ajuda`);
  console.log('');
}

// ─── CLI Argument Parsing ────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const flags = {
    new: false,
    update: false,
    force: false,
    version: false,
    help: false,
  };

  for (const arg of args) {
    switch (arg) {
      case '--new': case '-n': flags.new = true; break;
      case '--update': case '-u': flags.update = true; break;
      case '--force': case '-f': flags.force = true; break;
      case '--version': case '-v': flags.version = true; break;
      case '--help': case '-h': flags.help = true; break;
    }
  }

  return flags;
}

// ─── Readline Helper ─────────────────────────────────────────────────────────

function ask(rl, question) {
  return new Promise((resolve) => rl.question(question, resolve));
}

// ─── Copy Logic ──────────────────────────────────────────────────────────────

function countFiles(dir) {
  let count = 0;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) {
      count += countFiles(path.join(dir, entry.name));
    } else {
      count++;
    }
  }
  return count;
}

function copyFramework() {
  fs.cpSync(PACKAGE_CLAUDE_DIR, TARGET_CLAUDE_DIR, {
    recursive: true,
    force: true,
    filter: (source) => {
      const relative = path.relative(PACKAGE_CLAUDE_DIR, source);
      return !EXCLUDE_PATTERNS.some((p) => relative === p);
    },
  });
}

// ─── Session Backup/Restore ──────────────────────────────────────────────────

function backupSessions() {
  if (!fs.existsSync(SESSIONS_DIR)) return null;

  const timestamp = Date.now();
  const backupPath = path.join(TARGET_DIR, `.claude-sessions-backup-${timestamp}`);
  fs.renameSync(SESSIONS_DIR, backupPath);
  return backupPath;
}

function restoreSessions(backupPath) {
  if (!backupPath) return;
  fs.mkdirSync(path.dirname(SESSIONS_DIR), { recursive: true });
  fs.renameSync(backupPath, SESSIONS_DIR);
}

// ─── Handlers ────────────────────────────────────────────────────────────────

async function handleNewProject(rl, force) {
  const exists = fs.existsSync(TARGET_CLAUDE_DIR);

  if (exists && !force) {
    printWarning('Ja existe uma pasta .claude/ neste diretorio.');
    const answer = await ask(rl, `  Deseja sobrescrever? (s/N): `);
    if (answer.trim().toLowerCase() !== 's') {
      printWarning('Operacao cancelada.');
      return;
    }
  }

  if (exists) {
    printInfo('Removendo .claude/ existente...');
    fs.rmSync(TARGET_CLAUDE_DIR, { recursive: true, force: true });
  }

  printInfo(`Copiando framework Cortex v${VERSION}...`);
  copyFramework();

  const fileCount = countFiles(TARGET_CLAUDE_DIR);
  printSuccess(`Cortex instalado com sucesso! ${fileCount} arquivos copiados.`);
  printNextSteps();
}

async function handleUpdate(rl, force) {
  const exists = fs.existsSync(TARGET_CLAUDE_DIR);

  if (!exists) {
    printWarning('Nao foi encontrada uma pasta .claude/ neste diretorio.');
    printInfo('Use a opcao 1 (ou --new) para iniciar um novo projeto.');
    return;
  }

  if (!force) {
    printWarning(`Isso ira atualizar o framework para v${VERSION}.`);
    printInfo('Sua pasta sessions/ sera preservada.');
    const answer = await ask(rl, `  Deseja continuar? (s/N): `);
    if (answer.trim().toLowerCase() !== 's') {
      printWarning('Operacao cancelada.');
      return;
    }
  }

  printInfo('Fazendo backup da pasta sessions/...');
  const backupPath = backupSessions();

  if (backupPath) {
    printSuccess('Backup de sessions/ realizado.');
  } else {
    printInfo('Nenhuma pasta sessions/ encontrada (nada para preservar).');
  }

  printInfo('Removendo .claude/ antiga...');
  fs.rmSync(TARGET_CLAUDE_DIR, { recursive: true, force: true });

  printInfo(`Copiando framework Cortex v${VERSION}...`);
  copyFramework();

  if (backupPath) {
    printInfo('Restaurando pasta sessions/...');
    restoreSessions(backupPath);
    printSuccess('Pasta sessions/ restaurada.');
  }

  const fileCount = countFiles(TARGET_CLAUDE_DIR);
  printSuccess(`Cortex atualizado para v${VERSION}! ${fileCount} arquivos copiados.`);

  if (backupPath) {
    printSuccess('Sua pasta sessions/ foi preservada.');
  }

  printNextSteps();
}

// ─── Self-Install Guard ──────────────────────────────────────────────────────

function checkSelfInstall() {
  const packageDir = path.resolve(path.join(__dirname, '..'));
  const targetDir = path.resolve(TARGET_DIR);

  if (packageDir === targetDir) {
    printError('Voce esta executando o instalador dentro do proprio repositorio do Cortex.');
    printInfo('Execute este comando no diretorio do seu projeto.');
    process.exit(1);
  }
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const flags = parseArgs();

  if (flags.version) {
    console.log(`cortex-cdd v${VERSION}`);
    return;
  }

  if (flags.help) {
    printHelp();
    return;
  }

  checkSelfInstall();

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    if (flags.new) {
      printBanner();
      await handleNewProject(rl, flags.force);
      return;
    }

    if (flags.update) {
      printBanner();
      await handleUpdate(rl, flags.force);
      return;
    }

    printBanner();
    printMenu();

    const choice = await ask(rl, `  ${c.bold}Opcao:${c.reset} `);

    switch (choice.trim()) {
      case '1':
        console.log('');
        await handleNewProject(rl, flags.force);
        break;
      case '2':
        console.log('');
        await handleUpdate(rl, flags.force);
        break;
      case '0':
        console.log('');
        printWarning('Operacao cancelada.');
        break;
      default:
        console.log('');
        printError('Opcao invalida. Use 1, 2 ou 0.');
    }
  } finally {
    rl.close();
  }
}

main().catch((err) => {
  printError(`Erro inesperado: ${err.message}`);
  process.exit(1);
});
