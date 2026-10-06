#pragma once
#include "../sequencer/Pattern.h"
#include "EffectsRack.h"
#include "TonalVoice.h"
#include <atomic>
#include <memory>
namespace tessel {
static_assert(std::atomic<float>::is_always_lock_free);
static_assert(std::atomic<unsigned>::is_always_lock_free);
struct Hit {
    double beat;
    int track;
    float velocity, probability;
    int note = 60;
    double duration = .25;
    bool accent = false;
};
struct Snapshot {
    std::array<Hit, capacity * 8> hits{};
    int count = 0;
    Settings settings;
    std::array<VoiceParams, tracks> voices{};
    uint32_t seed = 1;
};
Snapshot compile(const Pattern &);
struct Trigger {
    uint64_t sample = 0, bar = 0;
    int track = 0;
    float strength = 0;
    double beat = 0;
    bool accent = false;
};
using TriggerCallback = void (*)(void *, const Trigger &);
class DrumEngine {
    struct Voice {
        double age = 10, phase = 0, phase2 = 0;
        float velocity = 0, low = 0;
        uint32_t noise = 1;
    };
    std::array<Voice, tracks> voices{};
    std::array<TonalVoice, 2> tonal;
    float duckEnvelope = 0;
    EffectsRack rack;
    Snapshot active;
    std::unique_ptr<Snapshot> pending = std::make_unique<Snapshot>();
    bool pendingValid = false;
    uint64_t totalSamples = 0;
    TriggerCallback onTrigger = nullptr;
    void *triggerContext = nullptr;
    double rate = 48000, position = 0;
    uint64_t loop = 0;
    int cursor = 0;
    std::array<float, 2> masterLow{}, held{};
    uint32_t dustNoise = 7351;
    int holdPhase = 0;
    static constexpr int delayCapacity = 96000;
    std::array<std::array<float, delayCapacity>, 2> delay{};
    std::array<float, 2> delayFilter{};
    int delayWrite = 0;
    float delayTailFeedback = 0;
    std::array<std::atomic<float>, tracks> meters{};
    float synth(int track);

  public:
    void prepare(double sampleRate);
    void setPattern(const Snapshot &s, bool quantized = true);
    void process(float *left, float *right, int count);
    float hitLevel(int track) const { return meters[track].load(std::memory_order_relaxed); }
    double beat() const { return position; }
    void reset();
    void seek(uint64_t sample);
    uint64_t mixedSamples() const { return totalSamples; }
    void setTriggerCallback(TriggerCallback callback, void *context) {
        onTrigger = callback;
        triggerContext = context;
    }
};
// Single-producer/single-consumer bounded queue: ownership transfers without locks.
class PatternQueue {
    std::array<Snapshot, 4> slots{};
    std::atomic<unsigned> read{0}, write{0};

  public:
    bool push(const Snapshot &s) {
        auto w = write.load(std::memory_order_relaxed);
        auto next = (w + 1) % 4;
        if (next == read.load(std::memory_order_acquire))
            return false;
        slots[w] = s;
        write.store(next, std::memory_order_release);
        return true;
    }
    bool pop(Snapshot &s) {
        auto r = read.load(std::memory_order_relaxed);
        if (r == write.load(std::memory_order_acquire))
            return false;
        s = slots[r];
        read.store((r + 1) % 4, std::memory_order_release);
        return true;
    }
};
} // namespace tessel
