#include "EffectsRack.h"
#include <numbers>
namespace tessel {
void EffectsRack::prepare(double sr) {
    rate = sr;
    reset();
}
void EffectsRack::reset() {
    for (auto &c : chorus)
        c.fill(0);
    for (auto &c : room)
        for (auto &line : c)
            line.fill(0);
    for (auto &c : stutter)
        c.fill(0);
    damping = {};
    widthLow = 0;
    low = {};
    held = {};
    smooth = {};
    combIndex = {};
    amounts = {};
    chorusIndex = stutterIndex = holdCounter = 0;
    stutterCell = -1;
}
void EffectsRack::process(float &left, float &right, const Settings &s, double beat) {
    for (int k = 0; k < effectCount; ++k)
        amounts[k] += ((k == 5 && (s.fxEnabled ? s.fx[k] : 0.f) < amounts[k]) ? .00006f : .0015f) *
                      ((s.fxEnabled ? s.fx[k] : 0.f) - amounts[k]);
    float signal[2] = {left, right}, decorrelated[2] = {};
    auto &a = amounts;
    int lengths[4] = {int(rate * .0297), int(rate * .0371), int(rate * .0411), int(rate * .0437)};
    int hold = 1 + int(a[1] * 24);
    if (holdCounter++ >= hold) {
        holdCounter = 0;
        for (int c = 0; c < 2; ++c)
            held[c] = signal[c];
    }
    int cellLength = std::clamp(int(samplesPerBeat(rate, s.bpm) * .25), 32, stutterSize);
    auto cell = int64_t(std::floor(beat * 4));
    if (cell != stutterCell) {
        stutterCell = cell;
        stutterIndex = 0;
    }
    int repeatLength = std::max(16, cellLength / 4);
    float wobble = float(.5 + .5 * std::sin(beat * 4 * std::numbers::pi));
    double cutoff = 18000 * std::pow(.02, double(a[2])) * (1 - a[3] * .9f + a[3] * wobble * .9f);
    float coefficient = float(1 - std::exp(-2 * std::numbers::pi * std::max(120., cutoff) / rate));
    for (int c = 0; c < 2; ++c) {
        float x = signal[c];
        float drive = 1 + a[0] * 10;
        float saturated = std::tanh(x * drive) / std::sqrt(drive);
        x = x * (1 - a[0]) + saturated * a[0];
        float levels = std::exp2(15 - a[1] * 11);
        float crushed = std::round(held[c] * levels) / levels;
        x = x * (1 - a[1]) + crushed * a[1];
        low[c] += coefficient * (x - low[c]);
        float filterMix = std::max(a[2], a[3]);
        x = x * (1 - filterMix) + low[c] * filterMix;
        chorus[c][chorusIndex] = x;
        double delay = rate * (.012 + .003 * std::sin(beat * std::numbers::pi * .5 + c * 1.8));
        delay = std::clamp(delay, 1., double(ringSize - 2));
        int whole = int(delay);
        float fraction = float(delay - whole);
        int read = (chorusIndex + ringSize - whole) % ringSize;
        float modulated = chorus[c][read] * (1 - fraction) +
                          chorus[c][(read + ringSize - 1) % ringSize] * fraction;
        decorrelated[c] = modulated;
        x = x * (1 - a[4] * .3f) + modulated * a[4] * .3f;
        float tail = 0;
        for (int line = 0; line < 4; ++line) {
            int length = std::clamp(lengths[line] + c * 31, 1, combSize);
            int pos = combIndex[c][line];
            float echo = room[c][line][pos];
            damping[c][line] += .22f * (echo - damping[c][line]);
            room[c][line][pos] = std::tanh(x * .2f + damping[c][line] * .72f);
            tail += echo;
            combIndex[c][line] = (pos + 1) % length;
        }
        x += tail * a[5] * .32f;
        if (stutterIndex < repeatLength)
            stutter[c][stutterIndex] = x;
        float repeated = stutter[c][stutterIndex % repeatLength];
        float gate =
            float(std::min(1., double(stutterIndex % repeatLength) / 16)) *
            float(std::min(1., double(repeatLength - 1 - stutterIndex % repeatLength) / 16));
        x = x * (1 - a[6]) + repeated * gate * a[6];
        signal[c] = x;
    }
    chorusIndex = (chorusIndex + 1) % ringSize;
    stutterIndex = (stutterIndex + 1) % cellLength;
    float difference = decorrelated[0] - decorrelated[1];
    widthLow += .03f * (difference - widthLow);
    float mid = (signal[0] + signal[1]) * .5f,
          side = (signal[0] - signal[1]) * .5f * (1 + a[7] * 2) +
                 a[7] * .15f * (difference - widthLow);
    float out[2] = {mid + side, mid - side};
    for (int c = 0; c < 2; ++c) {
        smooth[c] += .001f * (out[c] - smooth[c]);
        out[c] -= smooth[c];
    }
    // Bypass is exact when all controls have reached zero. No new noise is generated.
    bool active = false;
    for (float amount : a)
        active |= amount > 1e-6f;
    if (active) {
        left = out[0] / (1 + std::max(0.f, std::abs(out[0]) - .9f));
        right = out[1] / (1 + std::max(0.f, std::abs(out[1]) - .9f));
    }
}
} // namespace tessel
