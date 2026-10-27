import { mkdir, copyFile } from 'node:fs/promises';

const files = ['index.html', 'styles.css', 'mobile-polish.css', 'app.js', 'cloud-config.js'];
await mkdir(new URL('../web-dist/', import.meta.url), { recursive: true });
for (const file of files) {
  await copyFile(new URL(`../${file}`, import.meta.url), new URL(`../web-dist/${file}`, import.meta.url));
}
console.log('Web assets copied to web-dist/.');
