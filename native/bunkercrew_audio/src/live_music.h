#pragma once
#include "audio/DrumEngine.h"
#include "generator/BeatGenerator.h"
#include <memory>
#include <atomic>
#include <string>
namespace bunkercrew {
static_assert(std::atomic<uint64_t>::is_always_lock_free);
struct Theme {
 uint32_t seed=1;
 double bpm=100;
 int key=9, scale=0, personality=3, kickSound=0, hookStyle=0, phraseBars=8,restEvery=4,genre=0,initialIntensity=0,compositionVersion=1,scoreForm=0;
 float tone=.45f,punch=.45f,swing=.02f,dust=.03f,effects=.22f,bassWeight=.52f,melodyLevel=.32f,padLevel=.22f,room=.16f,density=.35f,phraseVariation=.32f,masterGain=1.f,normalizationDb=0.f;
 std::array<int,8> motif{0,2,1,4,2,0,-1,1};
};
struct MusicEvent {
 uint64_t sample=0,bar=0;
 int track=-1, kind=0;
 float strength=0;
 double beat=0;
 bool accent=false;
 uint64_t generation=0;
};
// Fixed, bounded SPSC event ring. Audio producer never allocates or waits.
template<typename T, unsigned Capacity> class Ring {
 std::array<T,Capacity> slots{};
 std::atomic<unsigned> read{0},write{0};
public:
 bool push(const T &v) {auto w=write.load(std::memory_order_relaxed),next=(w+1)%Capacity;if(next==read.load(std::memory_order_acquire))return false;slots[w]=v;write.store(next,std::memory_order_release);return true;}
 bool pop(T &v) {auto r=read.load(std::memory_order_relaxed);if(r==write.load(std::memory_order_acquire))return false;v=slots[r];read.store((r+1)%Capacity,std::memory_order_release);return true;}
};
struct PhraseBank {
 std::array<tessel::Snapshot,4> patterns;
 uint64_t bar=0;
 uint64_t generation=0;
};
class LiveMusic {
 Theme theme;
 double rate=48000;
 std::unique_ptr<tessel::DrumEngine> engine;
 std::array<std::unique_ptr<PhraseBank>,4> banks;
 Ring<unsigned,4> ready,freeSlots;
 Ring<MusicEvent,8192> events;
 std::atomic<uint64_t> mixed{0},requestedSeek{UINT64_MAX},intensityCommand{0},drops{0};
 std::atomic<uint64_t> transportGeneration{0};
 std::atomic<int> actualIntensity{0};
 std::atomic<bool> active{false};
 uint64_t generatedBar=0,nextBeat=0;
 uint64_t producerGeneration=0,activeGeneration=0;
 unsigned heldBank=0;
 unsigned preparedSlot=UINT32_MAX;
 bool hasHeldBank=false,needPattern=true,transportStarted=false;
 float postGain=1,dcLeft=0,dcRight=0,limiterGain=1,outputGain=0,arrangementGain=.48f;
 uint64_t interludeAt=UINT64_MAX;
 std::atomic<uint64_t> interludeRequest{UINT64_MAX};
 int activeCueKind=0;
 std::array<float,512> left{},right{};
 static void trigger(void *,const tessel::Trigger &);
 void emit(const MusicEvent &);
 int level_at(uint64_t bar,bool fromStart) const;
public:
 LiveMusic();
 void configure(const Theme &,double sampleRate);
 void prepare_phrases(); // main thread only
 void start(uint64_t sample=0);
 void stop();
 void seek(uint64_t sample);
 void request_intensity(int level,uint64_t atBar);
 void request_interlude(int kind,uint64_t sample);
 void process(float *left,float *right,int frames); // audio thread only
 bool poll(MusicEvent &event) {while(events.pop(event)){if(event.generation==transportGeneration.load(std::memory_order_acquire))return true;}return false;}
 uint64_t mixed_samples() const {return mixed.load(std::memory_order_acquire);}
 uint64_t dropped_events() const {return drops.load(std::memory_order_relaxed);}
 int intensity() const {return actualIntensity.load(std::memory_order_relaxed);}
 bool playing() const {return active.load(std::memory_order_relaxed);}
 double bpm() const {return theme.bpm;}
 double sample_rate() const {return rate;}
 int phrase_bars() const {return theme.phraseBars;}
 int genre() const {return theme.genre;}
 int composition_version() const {return theme.compositionVersion;}
 int score_form() const {return theme.scoreForm;}
 uint32_t seed() const {return theme.seed;}
 static tessel::Pattern compose(const Theme &,uint64_t phrase,int intensity);
};
}
