# Roadside cinematic recordings

Six original 48 kHz stereo PCM16 recordings supplement the three existing
travel scenes. They are played by scripts/travel_cinematic_sound.gd in the
game and in the development scene player.

| Scene | Continuous recording | Physical cue | Position |
| --- | --- | --- | --- |
| Signal | Verge wind and receiver acquiring lock | Relay contact at 3.4 s | Relay on the right |
| Storm | Irregular rain on the metal shelter | Tree fracture at 1.10 s; existing thunder at 1.15 s | Tree on the right; roof spread across stereo |
| Supply | Small generator catching at the pictured fan's start | Steel shutter at 1.6875 s | Generator just right of center; shutter on the right |

The scene player allocates one ambient player and three cue players. All use
the existing SFX bus, respect its slider and mute, and receive another 7 dB
attenuation while the selected crew recording speaks. No audio defaults or
editor bus effects are changed. Natural file endings have authored fades;
skipping the game scene fades the owned voices for 80 ms. Seeking consumes
past cues and resuming starts ambience from the selected point.

The existing air-contact flyover, thunder, and identity-matched DE/EN crew
recordings remain in use. This bank does not add substitute dialogue.

tools/generate_travel_cinematic_audio.py reproduces all six files from
deterministic synthesis without reading external samples. Adjacent source
JSON records the actual generator and WAV hashes, construction layers,
stereo placement, measurements, and Bunkercrew-only distribution notice.
sources.json also names the reused recordings.

Verification:

    python3 tests/travel_cinematic_audio_assets_test.py
    godot --headless --audio-driver Dummy --path . --script tests/travel_cinematic_audio_test.gd -- --no-profile-save --no-upnp
    godot --headless --audio-driver PulseAudio --path . --script tests/travel_cinematic_audio_test.gd -- --no-profile-save --no-upnp --native-audio

These checks measure PCM and exercise the mixer, pause, seek, stereo,
ducking, bus mute, and teardown. They do not replace listening assessment.
