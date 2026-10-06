#include "DrumEngine.h"
#include <numbers>
namespace tessel {
Snapshot compile(const Pattern &p) {
    Snapshot s;
    s.settings = p.settings;
    s.voices = p.voices;
    s.seed = p.seed;
    for (auto &e : p.events)
        for (int k = 0; k < e.ratchetCount && s.count < int(s.hits.size()); ++k)
            s.hits[s.count++] = {eventBeat(e, p.settings, k),
                                 e.instrument,
                                 e.velocity * std::pow(.83f, float(k)),
                                 e.probability,
                                 e.note,
                                 e.duration,
                                 e.accent};
    std::stable_sort(s.hits.begin(), s.hits.begin() + s.count,
                     [](auto &a, auto &b) { return a.beat < b.beat; });
    return s;
}
void DrumEngine::prepare(double sr) {
    rate = sr;
    reset();
}
void DrumEngine::reset() {
    for (auto &v : tonal)
        v.prepare(rate);
    duckEnvelope = 0;
    rack.prepare(rate);
    for (auto &channel : delay)
        channel.fill(0);
    delayWrite = 0;
    delayFilter = {};
    delayTailFeedback = 0;
    position = 0;
    totalSamples = 0;
    pendingValid = false;
    loop = 0;
    cursor = 0;
    masterLow = {};
    held = {};
    dustNoise = 7351;
    holdPhase = 0;
    for (int i = 0; i < tracks; ++i) {
        voices[i] = Voice{};
        voices[i].noise = uint32_t(i + 1) * 71871;
    }
}
void DrumEngine::setPattern(const Snapshot &s, bool quantized) {
    if (!quantized || (totalSamples == 0 && position == 0)) {
        active = s;
        position = std::fmod(totalSamples / samplesPerBeat(rate, active.settings.bpm), active.settings.bars * 4.);
        cursor = 0;
        while (cursor < active.count && active.hits[cursor].beat < position - .5 / samplesPerBeat(rate, active.settings.bpm)) ++cursor;
        return;
    }
    // Called by the audio consumer after PatternQueue::pop. Ownership is local;
    // std::vector generation/compile remain on the producer thread.
    *pending = s;
    pendingValid = true;
}
void DrumEngine::seek(uint64_t sample) {
    reset();
    totalSamples = sample;
    const double absoluteBeat = sample / samplesPerBeat(rate, active.settings.bpm);
    loop = uint64_t(absoluteBeat / (active.settings.bars * 4.));
    position = std::fmod(absoluteBeat, active.settings.bars * 4.);
    cursor = 0;
    while (cursor < active.count && active.hits[cursor].beat < position)
        ++cursor;
}
float DrumEngine::synth(int t) {
    if (isTonal(t))
        return tonal[t - bassTrack].process(t == bassTrack, active.voices[t], active.settings.tone,
                                            active.settings.punch, active.settings.hookStyle == 1,
                                            float(active.settings.bpm / 60.));
    auto &v = voices[t];
    auto p = active.voices[t];
    double age = v.age;
    v.age += 1 / rate;
    if (age > 2)
        return 0;
    v.noise ^= v.noise << 13;
    v.noise ^= v.noise >> 17;
    v.noise ^= v.noise << 5;
    float n = float(v.noise >> 8) / 8388608.f - 1;
    float bright = .035f + active.settings.tone * .55f;
    v.low += bright * (n - v.low);
    float hp = n - v.low;
    double freq = 100, decay = .05 * p.decay;
    float sound = 0;
    auto sine = [](double ph) { return std::sin(ph * 2 * std::numbers::pi); };
    switch (t) {
    case 0: {
        constexpr double base[] = {48, 36, 62, 45}, sweep[] = {150, 95, 170, 145},
                         length[] = {.105, .19, .055, .12};
        int soundIndex = active.settings.kickSound;
        freq = p.pitch *
               (base[soundIndex] + sweep[soundIndex] * (.7 + .6 * p.metal) * std::exp(-age * 70));
        decay = length[soundIndex] * p.decay;
        sound = float(sine(v.phase)) * (.6f + p.noise * .5f) +
                v.low * float(std::exp(-age * 350)) * (.025f + p.transient * .055f);
        if (soundIndex == 3)
            sound = std::tanh(sound * 2.8f) * .8f;
        sound = std::tanh(sound * (1 + active.settings.kickFx * 2));
        break;
    }
    case 1:
        freq = 175 * p.pitch;
        decay = .075 * p.decay;
        sound = float(sine(v.phase)) * .38f * float(std::exp(-age * 35)) +
                hp * (.55f + p.noise * .4f) + hp * float(std::exp(-age * 400)) * p.transient;
        break;
    case 2:
        freq = 400;
        decay = .12 * p.decay;
        sound =
            hp * float((std::exp(-age * 130) + (age > .011 ? std::exp(-(age - .011) * 160) : 0) +
                        (age > .023 ? std::exp(-(age - .023) * 45) : 0)) *
                       .7);
        break;
    case 3:
    case 4:
        freq = 4100 * p.pitch;
        decay = (t == 3 ? .014 : .14) * p.decay;
        sound = hp * .16f + float(sine(v.phase) * sine(v.phase * 1.447)) * .25f * p.metal;
        break;
    case 5:
        freq = p.pitch * (260 + 180 * std::exp(-age * 60));
        decay = .075 * p.decay;
        sound = float(sine(v.phase + 2.5 * sine(v.phase2) * std::exp(-age * 60))) * .65f + n * .08f;
        break;
    case 6:
        freq = 1800 * p.pitch;
        decay = .004 * p.decay;
        sound = float(sine(v.phase)) * .7f + hp * .25f;
        break;
    case 7:
        freq = 800;
        decay = .018 * p.decay;
        sound = v.low * (.6f + p.noise * .4f);
        break;
    }
    v.phase = std::fmod(v.phase + freq / rate, 1.);
    v.phase2 = std::fmod(v.phase2 + freq * 1.61 / rate, 1.);
    float env = float(std::exp(-age / std::max(decay, .001)));
    float attack = float(std::min(1., age * rate / 8));
    float drive = 1 + p.drive + active.settings.punch * .65f;
    return std::tanh(sound * drive) * env * attack * v.velocity;
}
void DrumEngine::process(float *l, float *r, int count) {
    double inc = 1 / samplesPerBeat(rate, active.settings.bpm);
    int delaySamples =
        std::clamp(int(samplesPerBeat(rate, active.settings.bpm) * .75), 1, delayCapacity - 1);
    for (int i = 0; i < count; ++i) {
        const double absoluteBeat = totalSamples / samplesPerBeat(rate, active.settings.bpm);
        const uint64_t bar = uint64_t(std::floor((totalSamples + .5) / samplesPerBeat(rate, active.settings.bpm) / 4.));
        const uint64_t barStart = uint64_t(std::llround(bar * 4. * samplesPerBeat(rate, active.settings.bpm)));
        if (pendingValid && totalSamples == barStart) {
            active = *pending;
            pendingValid = false;
            inc = 1 / samplesPerBeat(rate, active.settings.bpm);
            position = std::fmod(absoluteBeat + inc * .5, active.settings.bars * 4.);
            cursor = 0;
            while (cursor < active.count && active.hits[cursor].beat < position - inc * .5)
                ++cursor;
            // Keep voices, echo lines and EffectsRack alive across changes.
        }
        while (cursor < active.count && active.hits[cursor].beat <= position + inc * .5) {
            auto &h = active.hits[cursor++];
            uint32_t z = active.seed ^ uint32_t(bar * 0x9e3779b9u) ^
                         uint32_t(std::llround(h.beat * 960)) * 31337u ^ uint32_t(h.track * 71871);
            z ^= z << 13;
            z ^= z >> 17;
            z ^= z << 5;
            if (float(z >> 8) / 16777216.f < h.probability) {
                if (onTrigger)
                    onTrigger(triggerContext, Trigger{totalSamples, bar, h.track, h.velocity,
                              std::fmod(h.beat, 4.), h.accent});
                auto &v = voices[h.track];
                if (isTonal(h.track))
                    tonal[h.track - bassTrack].trigger(
                        h.note, h.duration * 60 / active.settings.bpm, h.velocity,
                        h.track == melodyTrack && active.settings.cinematicMelody,
                        h.track == melodyTrack && active.settings.warmStab);
                if (h.track == 0)
                    duckEnvelope = 1;
                v.noise = z ? z : 1;
                v.low = 0;
                v.age = 0;
                v.phase = 0;
                v.phase2 = 0;
                v.velocity = h.velocity;
                if (h.track == 3)
                    voices[4].age = 10;
            }
        }
        float a = 0, b = 0, send = 0;
        for (int t = 0; t < tracks; ++t) {
            float x = synth(t) * .3f;
            if (t == 0)
                x *= 1.15f;
            if (t == bassTrack)
                x *= active.settings.bassLevel * 1.35f * (1 - .68f * duckEnvelope);
            if (t == melodyTrack)
                x *= active.settings.melodyLevel * .85f * (1 - .25f * duckEnvelope);
            float pan = (t < 3 || t == bassTrack) ? 0
                        : t == melodyTrack        ? .12f
                                                  : float(t - 5) * .1f;
            float trackLeft = x * (1 - pan), trackRight = x * (1 + pan);
            if (t == 0)
                rack.process(trackLeft, trackRight, active.settings, position);
            a += trackLeft;
            b += trackRight;
            if (t == melodyTrack)
                send += x * .85f * active.settings.effects;
            else if (t == 1 || t == 5 || t == 6)
                send += x * .2f * active.settings.effects;
            else if (t == 0)
                send += x * .3f * active.settings.kickFx;
        }
        int delayed = (delayWrite + delayCapacity - delaySamples) % delayCapacity;
        float echoL = delay[0][delayed], echoR = delay[1][delayed];
        delayFilter[0] += .2f * (echoR - delayFilter[0]);
        delayFilter[1] += .2f * (echoL - delayFilter[1]);
        float fx = std::max(active.settings.effects, active.settings.kickFx);
        delayTailFeedback = std::max(fx, delayTailFeedback * .99995f);
        delay[0][delayWrite] = std::tanh(send + delayFilter[0] * .38f * delayTailFeedback);
        delay[1][delayWrite] = std::tanh(send * .7f + delayFilter[1] * .38f * delayTailFeedback);
        a += echoL * .7f;
        b += echoR * .7f;
        delayWrite = (delayWrite + 1) % delayCapacity;
        duckEnvelope *= float(std::exp(-1 / (rate * .075)));
        float dust = active.settings.dust;
        dustNoise ^= dustNoise << 13;
        dustNoise ^= dustNoise >> 17;
        dustNoise ^= dustNoise << 5;
        float texture = (float(dustNoise >> 8) / 8388608.f - 1) * dust * .003f *
                        std::min(1.f, (std::abs(a) + std::abs(b)) * 4);
        if (holdPhase++ >= int(dust * 5)) {
            held = {a, b};
            holdPhase = 0;
        }
        float cutoff = 1800 + active.settings.tone * 16000;
        float alpha = float(1 - std::exp(-2 * std::numbers::pi * cutoff / rate));
        auto color = [&](float x, int channel) {
            float character = x * (1 - dust * .25f) + held[channel] * dust * .25f + texture;
            auto y = std::tanh(character * (1 + dust * .4f));
            float quant = 2048 - 1800 * dust;
            y = y * (1 - dust * .25f) + std::round(y * quant) / quant * dust * .25f;
            masterLow[channel] += alpha * (y - masterLow[channel]);
            return masterLow[channel];
        };
        l[i] = color(a, 0);
        r[i] = color(b, 1);

        ++totalSamples;
        position += inc;
        if (position >= active.settings.bars * 4) {
            position -= active.settings.bars * 4;
            cursor = 0;
            ++loop;
        }
    }
    for (int t = 0; t < tracks; ++t)
        meters[t].store(isTonal(t) ? tonal[t - bassTrack].level()
                                   : voices[t].velocity * float(std::exp(-voices[t].age * 18)),
                        std::memory_order_relaxed);
}
} // namespace tessel
