import { cp, mkdir, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const web = resolve(root, 'web-dist');
const destination = resolve(root, 'android/app/src/main/assets/www');
await mkdir(dirname(destination), { recursive: true });
await rm(destination, { recursive: true, force: true });
await cp(web, destination, { recursive: true });
console.log(`Android assets copied from ${web}`);
