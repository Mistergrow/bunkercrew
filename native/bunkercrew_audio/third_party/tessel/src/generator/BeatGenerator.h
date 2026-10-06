#pragma once
#include "../sequencer/Pattern.h"
namespace tessel {
inline constexpr const char *personalities[] = {"MINIMAL", "BROKEN", "BUSY",  "MECHANICAL",
                                                "LOOSE",   "DUSTY",  "MICRO", "BURST"};
struct Random {
    uint32_t state;
    uint32_t next() {
        state += 0x9e3779b9;
        auto z = state;
        z = (z ^ (z >> 16)) * 0x21f0aaad;
        z = (z ^ (z >> 15)) * 0x735a2d97;
        return z ^ (z >> 15);
    }
    float unit() { return (next() >> 8) * (1.f / 16777216.f); }
    int choice(int n) { return int(next() % uint32_t(n)); }
};
Pattern generate(uint32_t seed, Settings settings, const Pattern *previous = nullptr);
Pattern mutate(const Pattern &pattern, uint32_t revision);
} // namespace tessel
