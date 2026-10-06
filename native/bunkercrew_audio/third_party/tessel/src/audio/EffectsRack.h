#pragma once
#include "../sequencer/Pattern.h"
namespace tessel {
inline constexpr int effectCount = 8;
inline constexpr const char *effectNames[] = {"DRIVE",  "CRUSH", "FILTER",  "WOBBLE",
                                              "CHORUS", "SPACE", "STUTTER", "WIDTH"};
class EffectsRack {
    static constexpr int ringSize = 8192, combSize = 4096, stutterSize = 32768;
    std::array<std::array<float, ringSize>, 2> chorus{};
    std::array<std::array<std::array<float, combSize>, 4>, 2> room{};
    std::array<std::array<float, 4>, 2> damping{};
    std::array<std::array<float, stutterSize>, 2> stutter{};
    std::array<float, 2> low{}, held{}, smooth{};
    float widthLow = 0;
    std::array<std::array<int, 4>, 2> combIndex{};
    std::array<float, effectCount> amounts{};
    int chorusIndex = 0, stutterIndex = 0, holdCounter = 0;
    int64_t stutterCell = -1;
    double rate = 48000;

  public:
    void prepare(double sampleRate);
    void reset();
    void process(float &left, float &right, const Settings &, double beat);
};
} // namespace tessel
