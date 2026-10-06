#include "TonalComposer.h"
#include "BeatGenerator.h"
namespace tessel {
namespace {
void note(Pattern &p, int track, double beat, int degree, float velocity, double length,
          bool anchor = false) {
    Event e;
    e.instrument = track;
    e.beatPosition = beat;
    e.note = scaleNote(p.settings, degree, track == bassTrack ? 2 : 4);
    e.velocity = velocity;
    e.duration = length;
    e.anchor = anchor;
    e.accent = velocity > .85f;
    // Bass follows the drum clock; hook responses sit slightly behind it.
    e.microTiming = anchor ? 0 : p.settings.human * (track == bassTrack ? .002 : .009);
    p.events.push_back(e);
}
} // namespace
void composeTonal(Pattern &p) {
    Random r{p.seed ^ 0xb451ca73};
    auto &s = p.settings;
    // A short seed-selected interval contour is repeated, not independently rolled per note.
    int motif[5] = {0, 1 + r.choice(2), 3, 1 + r.choice(3), 0};
    int contour = r.choice(3);
    if (contour == 1) {
        motif[1] = 3;
        motif[2] = 2;
        motif[3] = 1;
    }
    if (contour == 2) {
        motif[1] = 0;
        motif[2] = 3;
        motif[3] = 4;
    }
    int phraseRoots[4] = {0, 0, r.choice(2) ? 2 : 4, r.choice(2) ? 3 : 0};
    bool progression = r.choice(3) != 0;
    constexpr double backbones[4][5] = {{.5, 1., 1.75, 2.5, 3.25},
                                        {.25, .75, 1.5, 2.75, 3.5},
                                        {.5, 1.25, 2.5, 3., 3.5},
                                        {0, .75, 1.5, 2.25, 3.25}};
    std::array<double, 5> rhythm;
    std::copy(std::begin(backbones[s.hookStyle]), std::end(backbones[s.hookStyle]), rhythm.begin());
    rhythm[2] += (r.choice(3) - 1) * .125;
    rhythm[4] += (r.choice(3) - 1) * .125;
    for (int bar = 0; bar < s.bars; ++bar) {
        int root = progression ? phraseRoots[(bar / 2) % 4] : 0;
        double start = bar * 4.;
        // Kick-derived bass entries reserve silence before pickups and leave room for the hook.
        std::vector<double> kicks;
        for (auto &e : p.events)
            if (e.instrument == 0 && e.beatPosition >= start && e.beatPosition < start + 4 &&
                e.velocity > .55f)
                kicks.push_back(e.beatPosition - start);
        std::sort(kicks.begin(), kicks.end());
        kicks.erase(std::unique(kicks.begin(), kicks.end()), kicks.end());
        for (size_t i = 0; i < kicks.size(); ++i) {
            double offset = kicks[i];
            double delay = (s.hookStyle == 1 && i > 0) ? .25 : 0;
            double at = start + offset + delay;
            if (at >= start + 3.9)
                continue;
            double next = i + 1 < kicks.size() ? kicks[i + 1] + start : start + 4;
            double gate = std::clamp(next - at - .14, .12, s.hookStyle == 2 ? 1.25 : .7);
            note(p, bassTrack, at, root, i == 0 ? .88f : .73f, gate, i == 0);
        }
        if (kicks.empty())
            note(p, bassTrack, start, root, .88f, .6, true);
        if (s.hookStyle != 0 && s.activity > .25f &&
            std::none_of(p.events.begin(), p.events.end(), [&](auto &e) {
                return e.instrument == bassTrack && std::abs(e.beatPosition - (start + 3.5)) < .25;
            })) {
            double at = start + 3.5;
            note(p, bassTrack, at, root + (bar % 2 ? 3 : 0), .59f, .22);
        }
        if (s.hookStyle == 1 && s.activity > .55f) {
            note(p, bassTrack, start + .75, root + 3, .64f, .15);
            note(p, bassTrack, start + 1.5, root, .72f, .4);
        }
        int count = s.activity < .2f ? 2 : s.hookStyle == 3 ? 5 : 3;
        for (int k = 0; k < count; ++k) {
            int degree = motif[k] + root;
            bool returning = (bar % 2) == 1;
            double offset = rhythm[k];
            if (returning && k == count - 1)
                degree = root; // response resolves the motif
            if (returning && count >= 4 && k == count - 2 && s.chaos > .4f)
                degree = root + 2;
            note(p, melodyTrack, start + offset, degree,
                 k == 0           ? .82f
                 : k == count - 1 ? .66f
                                  : .57f,
                 (k == count - 1 ? .45 : .23), k == 0);
        }
    }
    // Monophonic gates end before the next note (including the loop boundary).
    for (int track : {bassTrack, melodyTrack}) {
        std::vector<size_t> indices;
        for (size_t i = 0; i < p.events.size(); ++i)
            if (p.events[i].instrument == track)
                indices.push_back(i);
        std::stable_sort(indices.begin(), indices.end(), [&](size_t a, size_t b) {
            return p.events[a].beatPosition < p.events[b].beatPosition;
        });
        for (size_t i = 0; i < indices.size(); ++i) {
            auto &e = p.events[indices[i]];
            double next = i + 1 < indices.size() ? p.events[indices[i + 1]].beatPosition
                                                 : p.events[indices[0]].beatPosition + s.bars * 4.;
            e.duration = std::max(.03, std::min(e.duration, next - e.beatPosition - .04));
        }
    }
}
} // namespace tessel
