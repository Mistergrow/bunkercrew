#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>
namespace tessel {
constexpr int drumTracks = 8, bassTrack = 8, melodyTrack = 9, tracks = 10, capacity = 2048;
inline constexpr const char *names[] = {"KICK", "SNARE", "CLAP",  "CLOSED HAT", "OPEN HAT",
                                        "PERC", "CLICK", "NOISE", "BASS",       "MELODY"};
struct Event {
    int instrument = 0;
    double beatPosition = 0;
    float velocity = .8f, probability = 1;
    double microTiming = 0;
    bool accent = false;
    int ratchetCount = 1;
    double ratchetSpacing = 1.0 / 32;
    bool anchor = false;
    int note = 60;
    double duration = .25;
    bool operator==(const Event &) const = default;
};
struct Settings {
    double bpm = 124;
    float swing = 0, activity = .35f, chaos = .12f, human = .08f, ratchet = 0, punch = .65f,
          dust = 0, tone = .4f, mutation = .3f;
    int bars = 4, personality = 1, key = 9, scale = 0, hookStyle = 0;
    float bassLevel = 0, melodyLevel = .55f, effects = 0, kickFx = 0;
    int kickSound = 0, kickRhythm = 0;
    std::array<float, 8> fx{};
    bool fxEnabled = true;
    bool cinematicMelody = false;
    bool warmStab = false;
    bool operator==(const Settings &) const = default;
};
struct VoiceParams {
    float pitch = 1, decay = 1, noise = .5f, drive = .25f, metal = .5f, transient = .5f;
    bool operator==(const VoiceParams &) const = default;
};
struct Pattern {
    uint32_t seed = 1;
    Settings settings;
    std::array<bool, tracks> locks{};
    std::array<VoiceParams, tracks> voices{};
    std::vector<Event> events;
    void sort() {
        std::stable_sort(events.begin(), events.end(), [](auto &a, auto &b) {
            return a.beatPosition + a.microTiming < b.beatPosition + b.microTiming;
        });
    }
};
inline double swung(double beat, float swing) {
    auto cell = std::floor(beat * 2);
    return beat + (static_cast<int>(cell) % 2 ? swing * .25 : 0);
}
inline double eventBeat(const Event &e, const Settings &s, int repeat = 0) {
    auto b = swung(e.beatPosition, s.swing) + e.microTiming + repeat * e.ratchetSpacing;
    auto length = s.bars * 4.;
    return std::fmod(b + length, length);
}
inline Pattern clearPattern(const Pattern &p) {
    auto empty = p;
    empty.events.clear();
    empty.locks.fill(false);
    return empty;
}
inline constexpr const char *kickSounds[] = {"ROUND", "SUB", "SHORT", "DRIVEN"};
inline constexpr const char *kickRhythms[] = {"AUTO", "STRAIGHT", "SYNCOPATED", "DOUBLE", "SPARSE"};
inline bool isTonal(int track) { return track >= bassTrack; }
inline constexpr int pentatonic[2][5] = {{0, 3, 5, 7, 10}, {0, 2, 4, 7, 9}};
inline constexpr const char *keys[] = {"C",  "C#", "D",  "D#", "E",  "F",
                                       "F#", "G",  "G#", "A",  "A#", "B"};
inline constexpr const char *hookStyles[] = {"KICK / HAT", "NEURO", "HALFTIME", "LIQUID"};
inline int scaleNote(const Settings &s, int degree, int octave) {
    int oct = degree / 5;
    int index = degree % 5;
    if (index < 0) {
        index += 5;
        --oct;
    }
    return octave * 12 + s.key + pentatonic[s.scale][index] + oct * 12;
}
inline bool inScale(int note, const Settings &s) {
    for (int offset : pentatonic[s.scale])
        if ((note - s.key + 120) % 12 == offset)
            return true;
    return false;
}
inline double samplesPerBeat(double rate, double bpm) { return rate * 60. / bpm; }
} // namespace tessel
