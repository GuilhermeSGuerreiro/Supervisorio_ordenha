#!/usr/bin/env node
// Grava o vídeo de demonstração quadro a quadro: render(t) na página, captura e ffmpeg.
// Uso:
//   node demo/video/gravar.cjs                       -> saida/scara-demo.mp4
//   node demo/video/gravar.cjs --quadros 3,14,30     -> saida/quadro-3.png ... (conferência)
// Requer: playwright (Node), Chromium e ffmpeg. dados.json vem de gerar_dados.py.
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const AQUI = __dirname;
const SAIDA = path.join(AQUI, 'saida');
const FPS = 30;

(async () => {
  fs.mkdirSync(SAIDA, { recursive: true });
  const dados = JSON.parse(fs.readFileSync(path.join(AQUI, 'dados.json'), 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => { console.error('erro na página:', e.message); process.exitCode = 1; });
  await page.goto('file://' + path.join(AQUI, 'video.html'));
  await page.evaluate(d => window.iniciar(d), dados);
  const duracao = await page.evaluate(() => window.DURACAO);

  const iq = process.argv.indexOf('--quadros');
  if (iq > 0) {
    for (const t of process.argv[iq + 1].split(',').map(Number)) {
      await page.evaluate(x => window.render(x), t);
      await page.screenshot({ path: path.join(SAIDA, `quadro-${t}.png`) });
      console.log(`quadro-${t}.png`);
    }
    await browser.close();
    return;
  }

  const destino = path.join(SAIDA, 'scara-demo.mp4');
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-vcodec', 'mjpeg', '-framerate', String(FPS), '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', destino],
    { stdio: ['pipe', 'inherit', 'inherit'] });
  const total = Math.round(duracao * FPS);
  for (let f = 0; f < total; f++) {
    await page.evaluate(x => window.render(x), f / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (f % (FPS * 10) === 0) console.log(`${Math.round(f / FPS)} s de ${Math.round(duracao)} s`);
  }
  ff.stdin.end();
  await new Promise((res, rej) => ff.on('close', c => c === 0 ? res() : rej(new Error('ffmpeg ' + c))));
  await browser.close();
  console.log(`pronto: ${destino} (${duracao} s, ${total} quadros)`);
})().catch(e => { console.error(e); process.exit(1); });
