#pragma once
#include "../sequencer/Pattern.h"
namespace tessel {
class TonalVoice {
    double sampleRate = 48000, age = 10, gate = .25, phase = 0, modPhase = 0, frequency = 110,
           target = 110;
    float velocity = 0, filter1 = 0, filter2 = 0, previous = 0, blendFrom = 0, envelope = 0;
    int blend = 0, blendTotal = 1;
    bool cinematicVoice = false, warmVoice = false;
    static double blep(double phase, double increment);

  public:
    void prepare(double rate);
    void trigger(int note, double duration, float velocity, bool cinematic = false, bool warm = false);
    float process(bool bass, const VoiceParams &, float tone, float punch, bool reese = false,
                  float movementHz = 2);
    float level() const { return envelope * velocity; }
};
} // namespace tessel
