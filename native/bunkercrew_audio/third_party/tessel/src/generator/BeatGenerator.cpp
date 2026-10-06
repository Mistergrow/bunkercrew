#include "BeatGenerator.h"
#include "TonalComposer.h"
namespace tessel {
namespace {
struct Profile {
    float activity, sync, timing, bursts;
};
constexpr Profile profiles[] = {
    {.55f, .4f, .6f, .4f}, {1, 1.3f, 1, 1},       {1.3f, .9f, .7f, 1.2f}, {.9f, 1.1f, 0, 1.1f},
    {.9f, .8f, 1.8f, .6f}, {.8f, .8f, 1.2f, .7f}, {.8f, 1.4f, .4f, 1.5f}, {1.1f, 1, .3f, 2}};
void add(std::vector<Event> &v, int track, double beat, float vel, bool anchor = false) {
    Event e;
    e.instrument = track;
    e.beatPosition = beat;
    e.velocity = vel;
    e.anchor = anchor;
    e.accent = vel > .88f;
    v.push_back(e);
}
// Gestures describe a contour, not a ready-made drum pattern.
void gesture(std::vector<Event> &v, Random &r, double origin, float activity, float bursts,
             float ratchet, int primary, int response) {
    int count = 2 + r.choice(1 + int(activity * 3));
    double spacing = (r.choice(3) == 0 ? 1. / 16
                      : r.choice(2)    ? 1. / 12
                                       : 1. / 24) *
                     (bursts > 1.4f ? .5 : 1);
    int direction = r.choice(3) == 0 ? -1 : 1;
    for (int k = 0; k < count; ++k) {
        auto b = origin + direction * k * spacing;
        if (b < 0 || b >= 4)
            continue;
        float contour = direction > 0 ? 1.f - k * .18f : .35f + k * .16f;
        add(v, k % 2 ? response : primary, b, .65f * contour);
        if (k == 0 && r.unit() < ratchet * bursts * .45f) {
            v.back().ratchetCount = 2 + r.choice(3);
            v.back().ratchetSpacing = 1. / (24 + r.choice(3) * 12);
        }
    }
}
} // namespace
Pattern generate(uint32_t seed, Settings s, const Pattern *old) {
    Pattern p;
    p.seed = seed;
    p.settings = s;
    if (old) {
        p.locks = old->locks;
        p.voices = old->voices;
    }
    Random r{seed};
    auto profile = profiles[std::clamp(s.personality, 0, 7)];
    float a = std::clamp(s.activity * profile.activity, 0.f, 1.f);
    std::vector<Event> core;
    if (s.hookStyle == 0) {
        int rhythm = s.kickRhythm == 0 ? 1 + r.choice(4) : s.kickRhythm;
        add(core, 0, 0, .96f, true);
        if (rhythm == 1) {
            for (int beat = 1; beat < 4; ++beat)
                add(core, 0, beat, .9f, true);
        }
        if (rhythm == 2) {
            add(core, 0, 1.5, .83f);
            add(core, 0, 2.5, .9f, true);
            if (a > .2f)
                add(core, 0, 3.5, .72f);
        }
        if (rhythm == 3) {
            add(core, 0, .75, .7f);
            add(core, 0, 2, .93f, true);
            add(core, 0, 2.75, .7f);
        }
        if (rhythm == 4)
            add(core, 0, 2, .93f, true);
        for (int beat = 0; beat < 4; ++beat)
            add(core, 3, beat + .5, .4f);
        if (a > .7f)
            for (int beat = 0; beat < 4; ++beat)
                add(core, 3, beat + .75, .23f);
    } else {
        add(core, 0, 0, .98f, true);
        int family = r.unit() < s.chaos * profile.sync ? r.choice(4) : r.choice(2);
        double response = family == 0 ? 2.5 : family == 1 ? 2. : family == 2 ? 1.75 : 2.75;
        add(core, 0, response, .84f, true);
        // Backbeat and broken backbeat retain a stable conversational relationship.
        if (s.hookStyle == 2) {
            add(core, 1, 2, .92f, true);
            if (a > .6f)
                add(core, 1, 3.75, .32f);
        } else {
            add(core, 1, 1, .85f, true);
            add(core, 1, 3., .92f, true);
        }
        if (a > .2f)
            add(core, 0, r.choice(2) ? 3.5 : .75, .64f);
        // Repeating ghost-snare cells bind the break together without disturbing the backbeat.
        if (s.hookStyle != 2 && a > .3f) {
            add(core, 1, r.choice(2) ? .75 : 1.75, .27f);
            add(core, 1, r.choice(2) ? 2.75 : 3.75, .34f);
        }
        if (s.hookStyle == 1 && a > .6f)
            gesture(core, r, 2.5, a, profile.bursts, s.ratchet, 1, 6);
        int pulse = a < .25f ? 4 : a > .55f ? 16 : 8;
        int hatOffset = pulse == 16 ? 0 : r.choice(2);
        int hatContour = r.choice(4);
        for (int k = 0; k < pulse; ++k) {
            float velocity = (k + hatContour) % 4 == 0 ? .62f : k % 2 ? .28f : .47f;
            add(core, 3, k * (4. / pulse) + (hatOffset ? .25 : 0),
                velocity * (.85f + r.unit() * .15f));
        }
        if (a > .5f) {
            int holes = 1 + r.choice(2);
            for (int k = 0; k < holes; ++k) {
                auto index = 4 + r.choice(int(core.size()) - 4);
                if (core[size_t(index)].instrument == 3)
                    core.erase(core.begin() + index);
            }
        }
        double motif = .5 + r.choice(6) * .5;
        if (r.unit() < s.chaos * .7f)
            motif += r.choice(2) ? 1. / 6 : -1. / 6;
        add(core, 5, motif, .62f);
        if (a > .25f)
            add(core, 6, std::fmod(motif + (r.choice(3) == 0 ? .75 : 1.25), 4.),
                .35f + r.unit() * .2f);
        if (a > .45f) {
            add(core, 4, 2.5, .45f);
            add(core, 2, 3., .38f);
        }
        if (a > .3f)
            gesture(core, r, 1.75, a, profile.bursts, s.ratchet, 5, 6);
        if (a > .65f)
            gesture(core, r, 3.5, a, profile.bursts, s.ratchet, 6, 7);
        if (a > .85f)
            gesture(core, r, .5, a, profile.bursts, s.ratchet, 3, 5);
    }
    // A phrase repeats timbre and accent contours as well as note positions.
    for (auto &e : core)
        if (!e.anchor)
            e.velocity *= .88f + r.unit() * .12f;
    int phraseShape = r.choice(3);
    for (int bar = 0; bar < s.bars; ++bar) {
        auto phrase = core;
        bool variation = bar > 0 && ((bar + phraseShape) % 2 == 1);
        if (variation && s.hookStyle != 0) {
            add(phrase, 0, 2.75, .48f);
            if (s.hookStyle != 2 && a > .45f) {
                add(phrase, 1, 3.5, .3f);
                if (a > .65f) {
                    add(phrase, 1, 3.75, .4f);
                    phrase.back().ratchetCount = s.ratchet > .6f ? 2 : 1;
                    phrase.back().ratchetSpacing = 1. / 16;
                }
            }
            if (a > .4f)
                gesture(phrase, r, 3.75, a, profile.bursts, s.ratchet, 5, 7);
        }
        if (s.hookStyle != 0 && bar == s.bars - 1 && s.bars > 1 && a > .3f)
            gesture(phrase, r, 3.5, a, profile.bursts, s.ratchet, 1, 6);
        for (auto e : phrase) {
            if (e.anchor)
                e.microTiming = 0;
            else {
                e.microTiming = s.human * profile.timing *
                                (e.instrument == 3   ? .018
                                 : e.instrument == 6 ? -.012
                                                     : .006);
                e.velocity *=
                    1 -
                    s.human * .12f * (e.instrument == 3 ? float(int(e.beatPosition * 2) % 2) : .5f);
            }
            e.beatPosition += bar * 4;
            p.events.push_back(e);
        }
    }
    // Bass must answer the drums actually heard, including retained locked kick events.
    if (old) {
        std::erase_if(p.events,
                      [&](auto &e) { return e.instrument < drumTracks && p.locks[e.instrument]; });
        for (auto &e : old->events)
            if (e.instrument < drumTracks && p.locks[e.instrument])
                p.events.push_back(e);
    }
    composeTonal(p);
    if (old) {
        std::erase_if(p.events, [&](auto &e) { return p.locks[e.instrument]; });
        for (auto &e : old->events)
            if (p.locks[e.instrument])
                p.events.push_back(e);
    }
    p.sort();
    return p;
}
Pattern mutate(const Pattern &old, uint32_t revision) {
    Pattern p = old;
    Random r{old.seed ^ (revision * 0x85ebca6b)};
    std::vector<size_t> eligible;
    for (size_t i = 0; i < p.events.size(); ++i)
        if (!p.locks[p.events[i].instrument] && !p.events[i].anchor)
            eligible.push_back(i);
    int budget = std::min(int(eligible.size()),
                          std::max(1, int(p.events.size() * (.1 + .1 * p.settings.mutation))));
    for (int k = 0; k < budget && !eligible.empty(); ++k) {
        int at = r.choice(int(eligible.size()));
        auto index = eligible[size_t(at)];
        eligible.erase(eligible.begin() + at);
        auto &e = p.events[index];
        switch (r.choice(5)) {
        case 0:
            e.velocity = std::clamp(e.velocity + (r.unit() - .5f) * .3f, .15f, .95f);
            break;
        case 1:
            e.microTiming = std::clamp(e.microTiming + (r.unit() - .5) * .025, -.04, .04);
            break;
        case 2:
            e.beatPosition = std::clamp(e.beatPosition + (r.choice(2) ? 1. : -1.) / 12, 0.,
                                        p.settings.bars * 4. - .125);
            break;
        case 3:
            if (isTonal(e.instrument)) {
                int degree = r.choice(5);
                e.note = scaleNote(p.settings, degree, e.instrument == bassTrack ? 2 : 5);
                e.duration = std::clamp(e.duration * (r.choice(2) ? .8 : 1.2), .1, 1.5);
            } else
                e.ratchetCount = e.ratchetCount > 1 ? 1 : 2 + r.choice(2);
            break;
        case 4:
            if (e.instrument >= 5 && e.instrument < drumTracks) {
                int target = 5 + r.choice(3);
                if (!p.locks[target])
                    e.instrument = target;
            } else
                e.velocity *= .9f;
            break;
        }
    }
    p.sort();
    return p;
}
} // namespace tessel
