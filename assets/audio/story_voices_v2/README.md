# Recorded character dialogue, version 2

The game ships 85 German and 85 English recordings for SAN, Mara, Branko, Ivo,
Nora, Levin, Selma, Oskar and Rika. Each of the eight playable crew members has
seven individual responses. The
original 50 English recordings retain their previous performances.

## Voice identity and provenance

Every new performance uses a fixed, entirely synthetic voice anchor for its
character. No real person's recording or identity was used. One anchor is
designed with [Qwen3-TTS VoiceDesign](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign),
then [Qwen3-TTS Base](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base)
conditions each sentence on that same recording and speaker embedding.
Both models use Apache-2.0; their pinned revisions, prompts, seeds and hashes
are recorded in `source.json` and `anchors/*.source.json`. Preserved English
files retain their original generation metadata. Models stay outside the game.

`lines.json` mirrors the authored catalog and shared locale tables. Recordings
are mono 24 kHz PCM16, with gentle rumble filtering, short fades and peak
headroom. SAN has a narrower radio spectrum. The game loads finished audio;
it needs no speech service, Python or model at runtime.

## Regeneration

Use `qwen-tts==0.1.1`, CUDA PyTorch, SoundFile and SciPy in an isolated environment.
Export inputs for both languages before generating changed text:

```bash
godot --headless --path . --script tools/export_story_voice_lines.gd -- --no-profile-save
godot --headless --path . --script tools/export_story_voice_lines.gd -- --locale=en --no-profile-save
python tools/generate_story_voices_v2.py
python tools/verify_story_voices_v2.py --transcribe --speaker-check
python tools/verify_story_voices_v2.py --locale en --transcribe --speaker-check
godot --headless --path . --editor --import --quit
```

Missing recordings resume automatically. Replace one sentence with
`--locale de --force --only mara_crew_wall`; its existing voice anchor stays fixed.
When the GPU is occupied, use matching CPU PyTorch/Torchaudio installations and
`--device cpu --threads 8 --speakers oskar rika --batch 1`. CPU generation uses
float32 by default and records the actual device and dtype in its provenance.
The two additional voices were generated from new synthetic anchors, rather
than by changing another character's pitch or processing the microphone chat.
Independent Whisper transcription checks wording. Hashes, waveform checks and
speaker comparisons catch corrupt files, exact duplicates and identity drift.
These checks do not replace listening: use the comparison page at
`artifacts/expedition/voices/index.html`. The coding model cannot consume audio.
The complete eight-character listening comparison is available at
`artifacts/character-identity-20261005/voices/index.html`.
