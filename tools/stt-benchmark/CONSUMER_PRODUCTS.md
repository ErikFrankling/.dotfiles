# Consumer-product comparison, checked 2026-09-19

Compare the actual product output, not a guessed underlying model. A free
web demo does not establish parity with every paid desktop configuration.
Access failures do not receive quality scores.

| Product / technology | Same-recording evidence | Free or direct test route | Remaining requirement |
|---|---|---|---|
| Wispr Flow / packaged contextual dictation | Official demo tested on a 349.952-second excerpt. It reversed the opening implementation request. Gemini and VibeVoice preserved it on that identical excerpt. | Browser demo; desktop free plan/trial also exists. | Desktop with dictionary and app context has not been tested. The full recording exceeds the demo's accepted duration. |
| Aqua / Avalon proprietary speech recognition | No valid transcript yet; earlier browser microphone integration did not work. | Official Avalon API accepts the full WAV and optional context/vocabulary prompt. | API dashboard requires authenticated Google, Apple, Microsoft or SSO login. No authenticated account was available in the automation browser. |
| Superwhisper / packaged speech recognition and optional editing | Fresh original-WAV upload through the actual browser UI returned HTTP 502; UI displayed transcription unavailable. | No-signup browser upload supports recordings up to ten minutes. | Working service or desktop trial. No quality conclusion from the failure. |
| Granola / live transcription followed by meeting notes | Not tested. Do not compare its summary with a dictation transcript. | Free account; desktop/mobile live transcription. | Official web app cannot transcribe; recorded-file imports are unsupported. Replay requires the desktop/mobile capture route and authenticated account. No official Linux app documented. |
| Otter / meeting transcription and notes | Not tested. | Basic free plan supports three lifetime audio/video imports; this recording fits the documented 30-minute recording limit. | Authenticated account. Sign-in page verified, but no account was connected. |

## Context hypothesis

Prioritize a model that can condition directly on both audio and relevant
project text. Extra processing passes did not establish a quality gain in
this recording. Prompt context changes the model's temporary internal state,
not its learned weights. Training/fine-tuning is what changes weights.

Gemini's observed lead does not isolate a cause: architecture, training,
capacity, prompts and provisional-reference bias are confounded. Supplying
more text was not monotonically better in the existing matched conditions.

Granola documents 30 personal jargon terms and 50 workspace terms. It explicitly
says blocks of text do not work as contextual paragraphs in that mechanism.
Its notes and chat can use transcripts, which is different from the speech
recognizer interpreting audio with rich project documents.

Avalon v1.5 exposes a `prompt` field for context/vocabulary hints. Its documented
batch route accepts WAV, up to 25 MiB and one hour of decoded audio. This does
not establish unlimited context or an audio-native general LLM architecture.
Compare plain audio and the same 18-name vocabulary first; then relevant
project text if the endpoint handles it. Keep this API result distinct from
the Aqua app's dictation/editing workflow. Published API price is $0.39/audio
hour, approximately $0.043 for one pass of this recording; free API credit
availability has not been verified. Do not equate desktop free words with API
credit.

## Sources and private evidence

- [Wispr pricing](https://wisprflow.ai/pricing)
- [Aqua API contract](https://aquavoice.com/docs/api)
- [Avalon API and pricing](https://aquavoice.com/avalon-api)
- [Superwhisper upload tool](https://superwhisper.com/transcribe)
- [Granola capture/import restrictions](https://docs.granola.ai/help-center/taking-notes/transcription)
- [Granola jargon/context limits](https://docs.granola.ai/help-center/customising-granola/customising-transcription)
- [Granola free signup](https://www.granola.ai/blog/granola-free-trial-get-started)
- [Otter free import limits](https://help.otter.ai/hc/en-us/articles/360047538094-Conversation-import-and-app-limits-on-the-Basic-free-plan)

Private evidence remains in ignored `results/frontier-round/`:
`consumer-access-probe.log`, `superwhisper-ui-recheck.json`, and
`excerpt350/comparison.json`. No fresh successful product transcript was
obtained during this access recheck; the existing 56 full-recording scores
are unchanged.
