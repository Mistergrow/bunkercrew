# Recorded character dialogue

These German and English lines are generated fictional voices for Mara, Branko, Ivo and SAN.
No recording or identity of a real person was used as a voice reference.

- Each language has 50 recordings, including the short grenade-launcher warning.
  German recordings live in this directory; English recordings live in `en/`.
  Each language has its own `lines.json` and `source.json`.
- `lines.json` mirrors the authored text in `scripts/story_dialogue_catalog.gd`
  and the shared `locales/` translation tables. English metadata also preserves
  the original German `source_text` for comparison.
- `source.json` records the exact model revision, text descriptions, seeds,
  mastering settings and SHA-256 checksum of each delivered recording.
- WAV files are mono, 24 kHz, PCM16. SAN has a restrained radio equalizer;
  the three workers retain their natural speech spectrum. Godot's normal QOA
  import compression reduces runtime memory; the source WAVs remain lossless.
- Generation model: [Qwen3-TTS VoiceDesign](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign),
  revision `5ecdb67327fd37bb2e042aab12ff7391903235d3`, Apache-2.0.
  [Model code and license](https://github.com/QwenLM/Qwen3-TTS).
  The downloaded model is kept outside the repository and is not shipped.

## Regenerate

Use an isolated Python environment with `qwen-tts==0.1.1`, compatible PyTorch,
SoundFile and SciPy. Generate only after reviewing the catalog text:

```bash
godot --headless --path . --script tools/export_story_voice_lines.gd
python tools/generate_story_voices.py --device cpu --threads 8
python tools/verify_story_voices.py --transcribe
godot --headless --path . --script tools/export_story_voice_lines.gd -- --locale=en --no-profile-save
python tools/generate_story_voices.py --locale en --device cpu --threads 8
python tools/verify_story_voices.py --locale en --transcribe
godot --headless --path . --editor --import --quit
```

The generator resumes missing files; `--force --only mara_crew_wall` replaces
one chosen line. Add `--locale en` for its English version. `--device cuda:0`
is available when the GPU is free.
Independent transcription uses the locally cached
[Whisper small](https://huggingface.co/openai/whisper-small) model, Apache-2.0;
audio never leaves the machine. Validation reports go to `artifacts/story-dialogue/`.
The game plays the finished recordings and requires no speech model or network.
Changing the local language restarts an active sentence with matching text and
audio. If a localized recording is missing, that language's subtitle remains
visible without substituting a voice from the other language.
