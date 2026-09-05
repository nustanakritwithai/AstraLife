import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  page.on('console', msg => console.log(`[browser:${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => console.error('[browser:error]', err));
  const target = pathToFileURL(path.resolve('index.html')).href;
  await page.goto(target, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.AstraLifeV051Acceptance && !!window.AstraLifeV051, null, { timeout: 15000 });
  const result = await page.evaluate(() => {
    runtime.state.running = false;
    runtime.reset('P0-CI-20260905');
    runtime.state.running = false;
    return window.AstraLifeV051Acceptance.run(1000);
  });
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}
