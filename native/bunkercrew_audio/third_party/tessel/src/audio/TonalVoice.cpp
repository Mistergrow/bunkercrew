#include "TonalVoice.h"
#include <numbers>
namespace tessel {
double TonalVoice::blep(double t, double dt) {
    if (t < dt) {
        t /= dt;
        return t + t - t * t - 1;
    }
    if (t > 1 - dt) {
        t = (t - 1) / dt;
        return t * t + t + t + 1;
    }
    return 0;
}
void TonalVoice::prepare(double sr) {
    sampleRate = sr;
    age = 10;
    phase = modPhase = 0;
    filter1 = filter2 = previous = envelope = 0;
    velocity = 0;
    blend = 0;
    cinematicVoice = warmVoice = false;
    frequency = target = 110;
}
void TonalVoice::trigger(int note, double duration, float vel, bool cinematic, bool warm) {
    cinematicVoice = cinematic;
    warmVoice = warm;
    bool idle = age > gate + .4;
    target = 440 * std::exp2((note - 69) / 12.);
    if (idle) {
        frequency = target;
        phase = modPhase = 0;
    }
    gate = duration;
    age = 0;
    velocity = vel;
    blendFrom = previous;
    blendTotal = std::max(1, int(sampleRate * (cinematicVoice ? .025 : .004)));
    blend = blendTotal;
}
float TonalVoice::process(bool bass, const VoiceParams &p, float tone, float punch, bool reese,
                          float movementHz) {
    if (age > gate + (cinematicVoice ? 2.6 : .5)) {
        envelope = 0;
        previous = 0;
        return 0;
    }
    double attack = bass ? .004 : cinematicVoice ? .065 : warmVoice ? .011 : .003;
    double release = cinematicVoice && !bass ? .48 : (bass ? .065 : warmVoice ? .14 : .09) * std::max(.25f, p.decay);
    float sustain = bass ? .78f : cinematicVoice ? .56f : warmVoice ? .36f : .18f;
    envelope =
        float(std::min(1., age / attack)) *
        (sustain +
         (1 - sustain) * float(std::exp(-age / ((bass ? .12 : .07) * std::max(.25f, p.decay)))));
    if (age > gate)
        envelope *= float(std::exp(-(age - gate) / release));
    frequency += (target - frequency) * (bass ? .0025 : cinematicVoice ? .001 : .03);
    double hz = std::clamp(frequency * double(p.pitch), 20., sampleRate * .2);
    double dt = hz / sampleRate;
    auto sine = [](double ph) { return std::sin(2 * std::numbers::pi * ph); };
    float sound;
    if (bass) {
        double saw = 2 * phase - 1 - blep(phase, dt);
        double triangle = 2 / std::numbers::pi * std::asin(sine(phase));
        float saw2 = float(2 * modPhase - 1 - blep(modPhase, dt * 1.006));
        float body = float(sine(phase)) * .66f + float(triangle) * .24f +
                     float(saw) * (.12f + p.noise * .24f) +
                     (reese ? saw2 * (.12f + p.noise * .16f) : 0);
        float cutoff =
            200 + tone * 1700 + p.metal * 900 + float(std::exp(-age * 18)) * p.transient * 1200;
        if (reese)
            cutoff *=
                float(.55 + .7 * (.5 + .5 * std::sin(age * 2 * std::numbers::pi * movementHz)));
        float alpha = float(1 - std::exp(-2 * std::numbers::pi * cutoff / sampleRate));
        filter1 += alpha * (body - filter1);
        filter2 += alpha * (filter1 - filter2);
        sound = std::tanh(filter2 * (1 + p.drive * 2 + punch * .4f)) * .92f;
    } else if (cinematicVoice) {
        const double triangle = 2 / std::numbers::pi * std::asin(sine(phase));
        const double saw = 2 * phase - 1 - blep(phase, dt);
        sound = float(sine(phase)) * .50f + float(sine(modPhase)) * .20f +
                float(triangle) * .21f + float(saw) * .035f;
        sound = std::tanh(sound * 1.1f);
    } else if (warmVoice) {
        // A rounded analogue answer rather than an FM bell. The short gate and
        // filtered harmonics keep the bassdrum clear without losing the motif.
        const double triangle = 2 / std::numbers::pi * std::asin(sine(phase));
        const double saw = 2 * phase - 1 - blep(phase, dt);
        const float body = float(sine(phase) * .60 + triangle * .27 + saw * .11);
        const float alpha = float(1 - std::exp(-2 * std::numbers::pi * (900 + tone * 2100) / sampleRate));
        filter1 += alpha * (body - filter1);
        sound = std::tanh(filter1 * (1.1f + p.drive * .35f));
    } else {
        double index = (.25 + p.metal * 1.7) * std::exp(-age * 12);
        sound = float(sine(phase + index * sine(modPhase))) * .64f +
                float(sine(phase * 2)) * .12f * float(std::exp(-age * 20));
        sound = std::tanh(sound * (1 + p.drive * .5f));
    }
    phase += dt;
    if (phase >= 1)
        phase -= 1;
    modPhase += dt * (bass ? 1.006 : cinematicVoice ? 1.003 : 2);
    if (modPhase >= 1)
        modPhase = std::fmod(modPhase, 1.);
    age += 1 / sampleRate;
    float out = sound * envelope * velocity;
    if (blend > 0) {
        float weight = float(blend) / float(blendTotal);
        out = out * (1 - weight) + blendFrom * weight;
        --blend;
    }
    previous = out;
    return out;
}
} // namespace tessel
