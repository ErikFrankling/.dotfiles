// Use the installed app's actual HTTP dictation function, not a substitute API model.
// Audited against Codex Desktop 26.915.31029; update the bundle/export only after review.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [audio, output, port = '19333'] = process.argv.slice(2);
if (!audio || !output || !/^\d+$/.test(port)) {
  throw new Error('Usage: node run_codex_desktop.mjs AUDIO.wav OUTPUT.json [local-debug-port]');
}
process.umask(0o077);
if (fs.existsSync(output)) throw new Error('Output exists; preserve previous runs');
const bytes = fs.readFileSync(audio);
if (bytes.subarray(0, 4).toString() !== 'RIFF' || bytes.subarray(8, 12).toString() !== 'WAVE') {
  throw new Error('Supply the original WAV recording');
}
let byteRate, audioBytes;
for (let offset = 12; offset + 8 <= bytes.length;) {
  const name = bytes.toString('ascii', offset, offset + 4);
  const size = bytes.readUInt32LE(offset + 4);
  if (offset + 8 + size > bytes.length) throw new Error('Incomplete WAV chunk');
  if (name === 'fmt ' && size >= 16) byteRate = bytes.readUInt32LE(offset + 16);
  if (name === 'data') audioBytes = size;
  offset += 8 + size + (size % 2);
}
if (!byteRate || !audioBytes) throw new Error('Missing WAV format or audio payload');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`, {
  signal: AbortSignal.timeout(5000),
})).json();
const target = targets.find(t => t.url === 'app://-/index.html');
if (!target) throw new Error('Codex Desktop main page is not available');
const socketUrl = new URL(target.webSocketDebuggerUrl);
if (!['127.0.0.1', 'localhost'].includes(socketUrl.hostname)) throw new Error('Expected local debugger');
const expression = `(async()=>{
  const m=await import('/assets/app-initial-3e128f859aa3.js');
  const bytes=Uint8Array.from(atob(${JSON.stringify(bytes.toString('base64'))}),x=>x.charCodeAt(0));
  if(typeof m.jM!=='function')throw Error('Audited dictation export is missing');
  const start=performance.now();
  try{return {text:await m.jM(new Blob([bytes],{type:'audio/wav'}),{
    filename:'codex.wav',contentType:'audio/wav',signal:AbortSignal.timeout(180000)
  }),elapsed_seconds:(performance.now()-start)/1000}}
  catch(e){return {error:String(e),status:e.status,elapsed_seconds:(performance.now()-start)/1000}}
})()`;
const ws = new WebSocket(socketUrl);
const result = await new Promise((resolve, reject) => {
  const timer = setTimeout(() => { ws.close(); reject(new Error('Desktop request deadline exceeded')); }, 195000);
  ws.onopen = () => ws.send(JSON.stringify({id: 1, method: 'Runtime.evaluate',
    params: {expression, awaitPromise: true, returnByValue: true}}));
  ws.onerror = () => { clearTimeout(timer); reject(new Error('Local debugger connection failed')); };
  ws.onmessage = event => {
    const data = JSON.parse(event.data);
    if (data.id !== 1) return;
    clearTimeout(timer); ws.close();
    if (data.error || data.result?.exceptionDetails) reject(new Error('Desktop evaluation failed'));
    else resolve(data.result.result.value);
  };
});
const record = {
  model: 'codex-desktop-dictation', technology: 'dedicated-asr-undisclosed',
  arm: path.basename(output, '.json'), clip: path.resolve(audio),
  audio_sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
  audio_seconds: audioBytes / byteRate,
  endpoint: 'Codex Desktop actual N0/jM HTTP dictation function /transcribe',
  desktop_bundle: 'app-initial-3e128f859aa3.js',
  elapsed_seconds: result.elapsed_seconds, response: {text: result.text ?? ''},
  returncode: result.error || !result.text ? 1 : 0, failure_kind: result.error ?? null,
  status: result.status, reference_used: false, completion_verified: false,
};
fs.mkdirSync(path.dirname(output), {recursive: true, mode: 0o700});
fs.writeFileSync(output, JSON.stringify(record, null, 2) + '\n', {flag: 'wx', mode: 0o600});
console.log(`Saved ${output}: ${record.returncode === 0 ? 'transcript returned' : record.failure_kind}`);
process.exitCode = record.returncode;
