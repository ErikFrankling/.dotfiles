# Codex on the actual long recording

**Codex is not the gold standard. Contextual cloud recognition has a demonstrated
advantage on the project names; no tested system is established as perfect.**

We submitted the entire original 398.739625-second WAV to Codex Desktop's actual
HTTP dictation function three times. This was not `gpt-transcribe` relabeled as
Codex, and no transcript or project context was supplied. All three returned
text through the final “Good”, in 7.3–7.5 seconds.

| Observation | Result |
|---|---|
| Codex project name, runs 1 / 2 / 3 | `Naya Cloud` / `Niaclaw` / `NyaCloud`; zero exact `naiaclaw` occurrences |
| Codex tool phrase | `Code-on Codex` / `code and codex` / `Code and Codex`; no `Claude Code` |
| Gemini Flash with the same 18-name prompt, two full runs | Nine exact `naiaclaw` occurrences and `Claude Code` in both |
| Local VibeVoice with vocabulary, whole recording | Nine exact `naiaclaw` occurrences; omits `Claude Code` |
| Codex repeat variation | 36–51 normalized word edits between pairs of runs |
| Gemini repeat variation | 59 normalized word edits; names stable, other wording not stable |

These edit counts measure reproducibility, not accuracy. Fillers, contractions,
number formatting and names contribute to them. Gemini's two requests had
identical request metadata and identical audio hashes. Its second output changes
“already” to “solely”, a potentially consequential regression despite correct names.

## Investigating differences against audio

Five excerpts totaling 204 seconds were sent independently to Gemini Flash and
GPT Audio: ten successful requests. Both received original audio and the frozen
18-name vocabulary, with **no draft, candidate answer or other model's output**.
This gives corroborating evidence, not human-verified ground truth.

- **Opening:** both recover `naiaclaw` and `Claude Code`. The intended spellings
  are established by the project/user, so this is a concrete vocabulary benefit.
- **Portal comparison:** both hear “the same as Portal”, supporting Codex over
  local VibeVoice's “someone's portal”.
- **Tenant creation:** both preserve the speaker changing their proposal. A
  rewritten, internally consistent plan would lose that self-correction.
- **Information from the script:** both hear “service script” and “already going
  to give us”. This supports Codex run 2 over run 1's “only”, and contradicts
  Gemini's second full run's “solely”. The earlier claim that “service script”
  was necessarily an error is withdrawn; occurrences must be judged separately.
- **Tone:** both use `Correct?`; one uses `Right?`, the other `Right.`. Codex varies
  between `Correct. Right.` and `correct? Right.`. The second question remains
  unresolved; these recordings do not establish general prosody accuracy.

The report contains **30 successful whole-recording conditions with the exact
same WAV hash**, complete text comparisons between any pair, and the five
playable investigation excerpts with both blind outputs. It excludes failed,
chunked, and draft-revision runs from that table. Thirty conditions are not thirty
independent model technologies. Earlier failed runs remain in their original artifacts.

Private report: `results/codex-long/study.html`. Rebuild it with
`python3 tools/stt-benchmark/long_study.py`. The underlying WAV, transcripts and
responses remain private and are not committed.

## Reproducing actual Codex dictation

Audited desktop: **26.915.31029**. Its
`webview/assets/app-initial-3e128f859aa3.js` exports `N0` as `jM`.
That function submits multipart audio to `/transcribe`; the desktop supplies
authentication and routing. It does not send the current project documents.
The underlying recognition model is not disclosed by the response.

The separately configured CLI 0.155.0 caused `Workspace routing is unavailable`
before upload. Using this desktop's **bundled 0.155.0-alpha.9 CLI** for the test
process fixed it. Saved Nix/desktop configuration was not changed. Direct Python
HTTP received a browser-verification page; the successful runs used the app's own
function and authenticated transport instead. Dictionary reads, including the
account header used by the UI, returned 404; no dictionary entries were changed.

`run_codex_desktop.mjs` is the reusable runner. Start this audited desktop with
its bundled CLI selected through `CODEX_CLI_PATH` and a local
`--remote-debugging-port=19333`, then run:

```sh
node tools/stt-benchmark/run_codex_desktop.mjs \
  ~/stt-tone-test.wav tools/stt-benchmark/results/codex-long/new-run.json
```

It calls the installed export, keeps credentials inside the app, records the
original audio hash, refuses existing outputs and bounds the upload deadline.
The third full recording run exercised this committed runner successfully.
The desktop bundle/export are pinned deliberately; review a changed app version
before updating them. Close the test desktop/debugger afterward.

## Limits of the conclusion

We now have the requested same-audio Codex comparison and investigated concrete
disagreements, including errors favoring each side. This single recording,
non-identical context access and machine-only adjudication cannot establish a
universal winner or an unquestionable accuracy percentage. Human correction of
the original audio is still required for a defensible WER/meaning-error ranking.
No such ranking is manufactured from Codex agreement.
