#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import readline from 'readline';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const args = process.argv.slice(2);
let signageDir = process.env.SIGNAGE_DIR || path.resolve(__dirname, '..');
let envFile = null;
let providedKey = null;
let nonInteractive = false;

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  switch (arg) {
    case '--signage-dir':
      signageDir = args[i + 1];
      i += 1;
      break;
    case '--env':
      envFile = args[i + 1];
      i += 1;
      break;
    case '--key':
      providedKey = args[i + 1] ?? '';
      i += 1;
      break;
    case '--non-interactive':
      nonInteractive = true;
      break;
    default:
      console.error(`Unknown argument: ${arg}`);
      process.exit(1);
  }
}

const resolvedEnvPath = envFile
  ? path.resolve(envFile)
  : path.join(path.resolve(signageDir), '.env');

const exampleEnvPath = path.join(path.resolve(signageDir), '.env.example');

function ensureEnvFile() {
  if (fs.existsSync(resolvedEnvPath)) {
    return;
  }

  if (fs.existsSync(exampleEnvPath)) {
    fs.copyFileSync(exampleEnvPath, resolvedEnvPath);
    console.log(`Created ${resolvedEnvPath} from template.`);
    return;
  }

  fs.writeFileSync(resolvedEnvPath, '');
  console.log(`Created empty ${resolvedEnvPath}.`);
}

function upsertEnvVar(content, key, value) {
  const lines = content.split(/\r?\n/);
  let updated = false;

  const newLines = lines.map((line) => {
    if (line.startsWith(`${key}=`)) {
      updated = true;
      return `${key}=${value}`;
    }
    return line;
  });

  if (!updated) {
    newLines.push(`${key}=${value}`);
  }

  return newLines.filter((line, index, arr) => {
    if (index === arr.length - 1 && line.trim() === '') {
      return false;
    }
    return true;
  }).join('\n') + '\n';
}

async function promptForKey() {
  if (!process.stdin.isTTY) {
    return null;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (query) => new Promise((resolve) => rl.question(query, resolve));

  const answer = await question('Enter CoreGeek Displays API key (leave blank to clear): ');
  rl.close();
  return answer.trim();
}

async function main() {
  ensureEnvFile();

  const envContent = fs.readFileSync(resolvedEnvPath, 'utf8');
  const currentLine = envContent
    .split(/\r?\n/)
    .find((line) => line.startsWith('CONTROLLER_API_KEY='));
  const currentValue = currentLine ? currentLine.split('=').slice(1).join('=') : '';

  let keyToWrite = providedKey ?? process.env.CONTROLLER_API_KEY ?? '';

  if (!keyToWrite) {
    if (nonInteractive) {
      console.error('API key not provided. Use --key or provide CONTROLLER_API_KEY.');
      process.exit(1);
    }

    const answer = await promptForKey();
    if (answer === null) {
      console.error('Interactive input is not available. Provide a key via --key.');
      process.exit(1);
    }
    keyToWrite = answer;
  }

  const normalizedValue = keyToWrite.trim();
  if (!normalizedValue && !currentValue) {
    console.log('API key remains unset.');
    return;
  }

  const updatedContent = upsertEnvVar(envContent, 'CONTROLLER_API_KEY', normalizedValue);
  fs.writeFileSync(resolvedEnvPath, updatedContent, 'utf8');

  if (normalizedValue) {
    console.log(`API key updated in ${resolvedEnvPath}.`);
  } else {
    console.log(`API key cleared in ${resolvedEnvPath}.`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
