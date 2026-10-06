#include "live_music.h"
#include <numbers>
#if defined(__SSE__) || defined(_M_X64)
#include <xmmintrin.h>
#endif
namespace bunkercrew {
namespace {
struct DenormalGuard {
#if defined(__SSE__) || defined(_M_X64)
 unsigned previous=_mm_getcsr();
 DenormalGuard(){_mm_setcsr(previous|0x8040u);}
 ~DenormalGuard(){_mm_setcsr(previous);}
#endif
};
}
tessel::Pattern compose_refreshed(const Theme &t,uint64_t phrase,int intensity) {
 tessel::Pattern p;
 p.seed=t.seed ^ uint32_t(phrase*0x9e3779b9u);
 auto &s=p.settings;
 s.bpm=t.bpm;s.bars=t.phraseBars;s.key=t.key;s.scale=t.scale;
 s.personality=t.personality;s.tone=t.tone;s.punch=t.punch;s.dust=t.dust*.26f;s.swing=t.swing*.38f;
 s.hookStyle=t.hookStyle;s.kickSound=t.kickSound;
 s.effects=t.effects*(intensity<2?.70f:.38f);
 s.bassLevel=t.bassWeight*(intensity==0?.38f:intensity==1?.76f:.96f);
 s.melodyLevel=t.melodyLevel*(intensity==0?2.30f:intensity==1?1.85f:.84f);
 s.cinematicMelody=intensity<=1;s.warmStab=intensity>=2;
 s.fx[5]=t.room*.32f;s.fx[4]=.015f;s.fx[7]=.035f;
 const bool relief=phrase%unsigned(t.restEvery)==unsigned(t.restEvery-1);
 tessel::Random random{p.seed},voiceRandom{t.seed};
 for(auto &v:p.voices){v.pitch=.97f+voiceRandom.unit()*.06f;v.drive=.08f+t.punch*.17f;v.decay=.72f+voiceRandom.unit()*.20f;v.metal=t.tone*.28f;v.noise=.16f+voiceRandom.unit()*.14f;}
 // Anchor voices remain tuned and centered. Kick decay has substantially faded
 // by the short offbeat sub, which releases before the following quarter.
 p.voices[0].pitch=1.f;p.voices[0].transient=.84f;p.voices[0].decay=t.kickSound==1?.69f:t.kickSound==2?.96f:.88f;
 p.voices[0].noise=.34f;p.voices[0].metal=.18f;
 p.voices[tessel::bassTrack].pitch=1.f;p.voices[tessel::bassTrack].decay=.58f;
 p.voices[tessel::bassTrack].noise=.16f;p.voices[tessel::bassTrack].metal=.03f;p.voices[tessel::bassTrack].drive=.11f;
 p.voices[tessel::melodyTrack].pitch=1.f;p.voices[tessel::melodyTrack].decay=intensity<2?.92f:.76f;
 p.voices[tessel::melodyTrack].metal=.025f;p.voices[tessel::melodyTrack].noise=.10f;p.voices[tessel::melodyTrack].drive=.08f;
 auto hit=[&](int track,double beat,float velocity,int degree=0,double duration=.18,bool accent=false){
  tessel::Event e;e.instrument=track;e.beatPosition=beat;e.velocity=velocity;e.probability=1;e.accent=accent;
  const int octave=track==tessel::bassTrack?2:4;
  if(t.scale<2)e.note=tessel::scaleNote(s,degree,octave);
  else{constexpr int intervals[2][7]={{0,2,3,5,7,9,10},{0,1,3,5,7,8,10}};int shift=int(std::floor(degree/7.));int cell=degree-shift*7;e.note=octave*12+t.key+intervals[t.scale-2][cell]+shift*12;}
  e.duration=duration;p.events.push_back(e);
 };
 for(int bar=0;bar<s.bars;++bar){
  const double b=bar*4.;
  const int cell=bar%8;
  const bool answer=cell>=4;
  const bool breath=(relief && cell>=4) || cell==7;
  const float kick=intensity==1?.48f:intensity==2?.80f:.89f;
  if(intensity==0){if(cell%4==0)hit(0,b,.24f,0,.18,true);}
  else for(int beat=0;beat<4;++beat)hit(0,b+beat,kick*(beat==0?1.03f:beat==2?1.f:.965f),0,.18,true);
  if(intensity==0){if(cell%2==0)hit(tessel::bassTrack,b,.25f,0,6.8);}
  else for(int beat=0;beat<4;++beat){
   // The last cell resolves in the tonic: no octave-leaping random bassline.
   int degree=answer&&cell==6&&beat==3?t.motif[6]:0;
   if(degree>3)degree=0;
   hit(tessel::bassTrack,b+beat+.5,.39f+.075f*intensity+(beat==0?.025f:0),degree,.16f);
  }
  // The hook is a repeatable question and answer. Longer carried notes in
  // construction become two low, rounded stabs in combat, with space to hear it.
  if(intensity<=1){
   if(!(cell==7&&relief))hit(tessel::melodyTrack,b,.59f*(.96f+random.unit()*t.phraseVariation*.20f),t.motif[cell],3.6);
  }else{
   if(cell%2==0)hit(tessel::melodyTrack,b+.75,.46f,t.motif[cell],.18);
   if((cell%2==1||intensity==3)&&!breath)hit(tessel::melodyTrack,b+2.75,.38f,t.motif[cell],.16);
   if(cell==7&&!relief)hit(tessel::melodyTrack,b+.75,.40f,0,.18);
  }
  if(intensity==0)continue;
  const float growth=.80f+.20f*float(cell)/7.f;
  for(int step=0;step<16;++step){
   const bool offbeat=step%4==2;
   const bool eighth=step%2==0;
   if(intensity==1&&!offbeat)continue;
   if(intensity==2&&!eighth && (cell<4||breath||t.density<.34f||step%4!=3))continue;
   if(intensity==3&&!eighth && (breath||t.density<.28f||step%4!=1))continue;
   if(breath&&!offbeat)continue;
   float velocity=(offbeat?.112f:eighth?.058f:.036f)*growth*(.97f+random.unit()*t.phraseVariation*.22f);
   hit(3,b+step*.25,velocity);
  }
  if(intensity>=2&&!breath){
   hit(2,b+1,.20f+(intensity==3?.028f:0));hit(2,b+3,.215f+(intensity==3?.028f:0));
   if(answer||intensity==3){hit(4,b+1.5,.105f);hit(4,b+3.5,.105f);}
   // One recurring low tom answer; no constantly changing metal clatter.
   if(cell%2==1)hit(5,b+2.5,.12f+random.unit()*.016f);
   if(intensity==3&&cell%4==2)hit(7,b+3.25,.095f);
  }else if(intensity==1&&cell%2==1&&!relief)hit(6,b+3,.055f);
  if(cell==6&&intensity>=2&&!relief){hit(5,b+3.5,.11f);hit(3,b+3.75,.085f);}
  // A little air before the next downbeat makes the return powerful. It never
  // removes the real four-quarter kick or invents fake visual hit markers.
 }
 p.sort();return p;
}

LiveMusic::LiveMusic():engine(std::make_unique<tessel::DrumEngine>()) {
 for(unsigned i=0;i<banks.size();++i){banks[i]=std::make_unique<PhraseBank>();if(i<3)freeSlots.push(i);}
}
tessel::Pattern LiveMusic::compose(const Theme &t,uint64_t phrase,int intensity) {
 if(t.compositionVersion>=2&&t.genre==0)return compose_refreshed(t,phrase,intensity);
 tessel::Pattern p;
 p.seed=t.seed ^ uint32_t(phrase*0x9e3779b9u);
 auto &s=p.settings;
 s.bpm=t.bpm;s.bars=t.phraseBars;s.key=t.key;s.scale=t.scale;
 s.personality=t.personality;s.tone=t.tone;s.punch=t.punch;s.dust=t.dust*.42f;s.swing=t.swing*.55f;
 s.hookStyle=t.hookStyle;s.kickSound=t.kickSound;s.effects=t.effects*.6f;
 s.bassLevel=t.bassWeight*(intensity==0?.46f:.64f+.12f*intensity);s.melodyLevel=intensity==0?.95f:intensity==1?.70f:.18f+.025f*intensity;
 s.cinematicMelody=intensity<=1;
 s.fx[5]=t.room*.45f;s.fx[4]=.025f;s.fx[7]=.07f;
 if(t.genre==1){s.kickSound=3;s.swing=0;s.kickFx=intensity>1?.18f:.05f;s.fx[0]=intensity>1?.23f:.09f;s.fx[1]=.025f;s.hookStyle=intensity>=2?1:0;}
 if(t.genre==2){s.kickSound=0;s.swing=std::max(s.swing,.19f);s.dust=std::max(s.dust,.16f);s.fx[5]=t.room*.32f;}
 if(t.genre==3){s.kickSound=2;s.swing=std::max(s.swing,.08f);s.hookStyle=intensity>=2?1:0;s.fx[5]=t.room*.55f;}
 // Minimal techno shares a stable four-on-the-floor foundation across themes.
 // Identity comes from tonic, bass pickups, transient colour and restrained space.
 tessel::Random random{p.seed},voiceRandom{t.seed};
 const int section=int(phrase%8);
 for(auto &v:p.voices){v.pitch=.94f+voiceRandom.unit()*.12f;v.drive=.12f+t.punch*.22f;v.decay=.76f+voiceRandom.unit()*.22f;v.metal=t.tone*.55f;v.noise=.22f+voiceRandom.unit()*.24f;}
 p.voices[0].transient=.72f;p.voices[0].decay=t.kickSound==1?.78f:.92f;
 p.voices[tessel::melodyTrack].pitch=1.f;p.voices[tessel::bassTrack].pitch=1.f;
 p.voices[tessel::bassTrack].decay=.78f;p.voices[tessel::bassTrack].noise=.32f;
 p.voices[tessel::melodyTrack].decay=.48f;p.voices[tessel::melodyTrack].metal=.04f+t.tone*.12f;
 p.voices[tessel::melodyTrack].noise=.12f;p.voices[tessel::melodyTrack].drive=.10f;
 auto hit=[&](int track,double beat,float velocity,int degree=0,double duration=.18,bool accent=false){
  tessel::Event e;e.instrument=track;e.beatPosition=beat;e.velocity=velocity;e.probability=1;e.accent=accent;
  const int octave=track==tessel::bassTrack?3:4;
  if(t.scale<2)e.note=tessel::scaleNote(s,degree,octave);
  else{constexpr int intervals[2][7]={{0,2,3,5,7,9,10},{0,1,3,5,7,8,10}};int shift=int(std::floor(degree/7.));int cell=degree-shift*7;e.note=octave*12+t.key+intervals[t.scale-2][cell]+shift*12;}
  e.duration=duration;p.events.push_back(e);
 };
 for(int bar=0;bar<s.bars;++bar){
  const double b=bar*4.;
  const bool breath=section==4 && bar%4==3;
  const bool pickup=bar==s.bars-1;
  const float kick=intensity==1?.44f:intensity==2?.75f:.88f;
  // Never remove or displace the pulse to create variation: walking animation
  // and gameplay remain independent, while the heard groove stays unambiguous.
  if(intensity==0){if(bar%4==0)hit(0,b,.28f,0,.18,true);}
  else if(t.genre<2){for(int beat=0;beat<4;++beat)hit(0,b+beat,kick*(beat==0?1.04f:.98f),0,.18,true);}
  else if(t.genre==2){hit(0,b,kick*1.04f,0,.18,true);hit(0,b+1.5,kick*.84f,0,.18,true);hit(0,b+2.5,kick*.93f,0,.18,true);if(intensity==3&&bar%2==1)hit(0,b+3.25,kick*.63f,0,.18,true);}
  else{hit(0,b,kick*1.04f,0,.18,true);hit(0,b+1.5,kick*.86f,0,.18,true);hit(0,b+2.75,kick*.90f,0,.18,true);if(intensity==3&&bar%2)hit(0,b+3.5,kick*.64f,0,.18,true);}
  // A short offbeat bass cell leaves each kick transient its own low-end space.
  if(intensity==0)hit(tessel::bassTrack,b,.32f,0,3.2f);
  for(int beat=0;beat<4&&intensity>0&&t.genre<2;++beat){
   int degree=0;
   if(intensity>=2 && bar%4==3 && beat==3)degree=t.motif[(bar+int(phrase))%8];
   hit(tessel::bassTrack,b+beat+.5f,.36f+.075f*intensity,degree,.19f);
  }
  if(intensity>0&&t.genre==2){hit(tessel::bassTrack,b+.25,.46f+.055f*intensity,0,.62);hit(tessel::bassTrack,b+1.75,.38f,t.motif[(bar+int(phrase))%8],.38);hit(tessel::bassTrack,b+2.75,.43f,0,.55);}
  if(intensity>0&&t.genre==3){hit(tessel::bassTrack,b+.5,.48f+.04f*intensity,0,.24);hit(tessel::bassTrack,b+2,.42f,0,.24);hit(tessel::bassTrack,b+3.5,.42f,t.motif[(bar+int(phrase))%8],.20);}
  if(intensity>=3 && pickup && !breath && t.genre<2)hit(tessel::bassTrack,b+3.75,.28f,0,.10f);
  // Level 0 keeps a quiet eighth-note offbeat. Higher levels add controlled
  // sixteenths and open-hat air, with a small phrase variation in velocities.
  for(int step=0;step<16&&intensity>0;++step){
   bool offbeat=step%4==2;
   if(t.genre==2){if(step%2==1&&intensity<3)continue;if(step%2==1&&step%8!=7)continue;}
   else if(intensity<=1 && !offbeat)continue;
   if(t.genre==0 && intensity==2 && step%2==1 && (step+bar)%4!=1)continue;
   if(breath && !offbeat)continue;
   if(t.genre==3&&intensity==1&&step%2)continue;
   float hat=offbeat?(.08f+.035f*intensity):(.045f+.012f*intensity);
   hat*=.91f+random.unit()*(.10f+t.phraseVariation*.18f);
   hit(3,b+step*.25,hat);
  }
  if(intensity>0&&t.genre>=2&&!breath){
   float snare=intensity==1?.23f:intensity==2?.45f:.53f;
   hit(1,b+1,snare);hit(1,b+3,snare*1.02f);
   if(t.genre==3&&intensity>=2){hit(1,b+2.625,.12f);if(bar%2)hit(1,b+3.75,.095f);}
   if(intensity==3){hit(2,b+3,.12f);hit(4,b+3.5,.13f);}
  }
  else if(intensity>=2&&!breath){
   for(int beat=0;beat<4;++beat){if(intensity==2&&beat%2==0)continue;hit(4,b+beat+.5,.11f+.016f*intensity);}
   hit(2,b+1,.18f+.018f*intensity);hit(2,b+3,.18f+.018f*intensity);
   if(intensity==3){hit(1,b+1,.25f);hit(1,b+3,.27f);}
  }else if(intensity==1&&!breath&&t.genre<2){hit(6,b+1,.085f);hit(6,b+3,.085f);}
  if(t.genre==1&&intensity>=2&&!breath){for(int beat=0;beat<4;++beat)hit(7,b+beat+.5,.10f+.03f*intensity);}
  if(intensity>=2&&!breath){
   hit(5,b+(t.personality==1?1.75:1.5),.15f+random.unit()*.045f);
   if(intensity==3)hit(5,b+3.25,.13f);
   if(t.personality==3&&intensity==3&&bar%2==1)hit(6,b+.75,.07f);
  }
  // Replace the old upper-register arpeggio with one short, low, percussive stab.
  // Silence between stabs is an arrangement choice, not a changing random tune.
  if(intensity<=1 && bar%2==0 && !(section==4&&bar%8==6)){
   int note=t.motif[(bar/2+int(phrase%2)*4)%8];
   hit(tessel::melodyTrack,b,(intensity==0?.64f:.53f)+random.unit()*.04f,note,7.25);
  }
  bool stab=intensity==2?bar%2==1:intensity==3;
  if(stab&&!breath){int degree=bar%4==3?t.motif[(bar+int(phrase))%8]:0;hit(tessel::melodyTrack,b+(bar%2?2.75:.75),.18f+.025f*intensity,degree,.12);}
  // A restrained last-beat fill announces the next phrase without breaking 4/4.
  if(pickup&&intensity>=2&&!breath){hit(3,b+3.5,.15f);hit(5,b+3.75,.16f);if(intensity==3)hit(7,b+3.75,.10f);}
 }
 p.sort();return p;
}
void LiveMusic::configure(const Theme &t,double sr){
 theme=t;theme.bpm=std::isfinite(theme.bpm)?std::clamp(theme.bpm,45.,180.):100.;theme.phraseBars=theme.phraseBars==16?16:8;
 auto unit=[](float &v,float fallback){v=std::isfinite(v)?std::clamp(v,0.f,1.f):fallback;};
 unit(theme.tone,.45f);unit(theme.punch,.45f);unit(theme.swing,.02f);unit(theme.dust,.03f);unit(theme.effects,.22f);unit(theme.bassWeight,.52f);unit(theme.melodyLevel,.32f);unit(theme.padLevel,.22f);unit(theme.room,.16f);unit(theme.density,.35f);unit(theme.phraseVariation,.32f);
 theme.masterGain=std::isfinite(theme.masterGain)?std::clamp(theme.masterGain,0.f,2.f):1.f;
 theme.normalizationDb=std::isfinite(theme.normalizationDb)?std::clamp(theme.normalizationDb,-12.f,3.f):0.f;
 theme.genre=std::clamp(theme.genre,0,3);theme.personality=std::clamp(theme.personality,0,7);theme.hookStyle=std::clamp(theme.hookStyle,0,3);theme.restEvery=std::clamp(theme.restEvery,2,16);
 // A late join inherits the currently playing arrangement independently of a
 // future host command. Initialize both values before publishing the session.
 theme.compositionVersion=std::clamp(theme.compositionVersion,1,2);theme.scoreForm=std::clamp(theme.scoreForm,0,1);
 theme.initialIntensity=std::clamp(theme.initialIntensity,0,3);
 actualIntensity.store(theme.initialIntensity,std::memory_order_relaxed);
 intensityCommand.store(uint64_t(theme.initialIntensity),std::memory_order_relaxed);
 for(auto &degree:theme.motif)degree=std::clamp(degree,-14,14);
 theme.key=std::clamp(theme.key,0,11);theme.scale=std::clamp(theme.scale,0,3);theme.kickSound=std::clamp(theme.kickSound,0,3);
 postGain=std::pow(10.f,std::clamp(theme.normalizationDb,-12.f,3.f)/20.f);
 rate=std::isfinite(sr)?std::clamp(sr,22050.,192000.):48000.;engine->prepare(rate);
 prepare_phrases();
}
void LiveMusic::prepare_phrases(){
 unsigned slot;
 const uint64_t generation=transportGeneration.load(std::memory_order_acquire);
 const uint64_t audibleBar=uint64_t(mixed.load(std::memory_order_acquire)/(rate*60/theme.bpm*4));
 if(generation!=producerGeneration){producerGeneration=generation;generatedBar=(audibleBar/theme.phraseBars)*theme.phraseBars;}
 generatedBar=std::max(generatedBar,(audibleBar/theme.phraseBars)*theme.phraseBars);
 // Only the producer writes ready, and only the audio consumer writes freeSlots.
 // Retain a prepared slot locally if publication ever meets a full ready ring.
 if(preparedSlot!=UINT32_MAX){if(!ready.push(preparedSlot))return;preparedSlot=UINT32_MAX;}
 while(freeSlots.pop(slot)){
  auto &bank=*banks[slot];bank.bar=generatedBar;bank.generation=generation;
  for(int i=0;i<4;++i)bank.patterns[i]=tessel::compile(compose(theme,generatedBar/theme.phraseBars,i));
  generatedBar+=theme.phraseBars;
  if(!ready.push(slot)){preparedSlot=slot;break;}
 }
}
void LiveMusic::start(uint64_t sample){requestedSeek.store(sample,std::memory_order_release);active.store(true,std::memory_order_release);}
void LiveMusic::stop(){active.store(false,std::memory_order_release);}
void LiveMusic::seek(uint64_t sample){requestedSeek.store(sample,std::memory_order_release);}
void LiveMusic::request_intensity(int level,uint64_t bar){intensityCommand.store((bar<<2)|uint64_t(std::clamp(level,0,3)),std::memory_order_release);}
void LiveMusic::request_interlude(int kind,uint64_t sample){interludeRequest.store((sample<<2)|uint64_t(std::clamp(kind,0,3)),std::memory_order_release);}
void LiveMusic::emit(const MusicEvent &e){auto stamped=e;stamped.generation=activeGeneration;if(!events.push(stamped))drops.fetch_add(1,std::memory_order_relaxed);}
void LiveMusic::trigger(void *context,const tessel::Trigger &t){auto self=static_cast<LiveMusic*>(context);self->emit({t.sample,t.bar,t.track,0,t.strength,t.beat,t.accent});}
int LiveMusic::level_at(uint64_t bar,bool fromStart) const{
 int level=fromStart?theme.initialIntensity:actualIntensity.load(std::memory_order_relaxed);
 const auto command=intensityCommand.load(std::memory_order_acquire);
 if(bar>=(command>>2))level=int(command&3);
 if(theme.scoreForm==1){constexpr int form[4]={0,1,2,1};level=form[(bar/theme.phraseBars)%4];}
 return level;
}
void LiveMusic::process(float *outLeft,float *outRight,int frames){
 DenormalGuard denormalGuard;
 if(!active.load(std::memory_order_acquire)){std::fill_n(outLeft,frames,0);std::fill_n(outRight,frames,0);return;}
 const double spb=tessel::samplesPerBeat(rate,theme.bpm);
 uint64_t seekTo=requestedSeek.exchange(UINT64_MAX,std::memory_order_acq_rel);
 if(seekTo!=UINT64_MAX){
  const bool reuseOpening=!transportStarted && seekTo<uint64_t(std::llround(theme.phraseBars*4*spb));
  engine->seek(seekTo);mixed.store(seekTo,std::memory_order_release);nextBeat=uint64_t(std::ceil(seekTo/spb-1e-10));outputGain=0;needPattern=true;
  dcLeft=dcRight=0;limiterGain=1;interludeAt=UINT64_MAX;
  actualIntensity.store(level_at(uint64_t(std::floor((seekTo+.5)/spb))/4,true),std::memory_order_relaxed);
  if(!reuseOpening){++activeGeneration;transportGeneration.store(activeGeneration,std::memory_order_release);}
  transportStarted=true;
 }
 engine->setTriggerCallback(&LiveMusic::trigger,this);
 int done=0;
 while(done<frames){
  uint64_t sample=mixed.load(std::memory_order_relaxed);
  uint64_t beat=uint64_t(std::floor((sample+.5)/spb));
  uint64_t bar=beat/4;
  // Dequeue generated banks without copying or destroying them on the audio thread.
  if(!hasHeldBank)hasHeldBank=ready.pop(heldBank);
  while(hasHeldBank && (banks[heldBank]->generation!=activeGeneration || banks[heldBank]->bar+theme.phraseBars<=bar)){freeSlots.push(heldBank);hasHeldBank=ready.pop(heldBank);}
  uint64_t phraseStart=uint64_t(std::llround((bar/theme.phraseBars)*theme.phraseBars*4*spb));
  if(hasHeldBank && banks[heldBank]->bar<=bar && (sample==phraseStart || needPattern)){
   const int level=level_at(bar,false);
   actualIntensity.store(level,std::memory_order_relaxed);
   engine->setPattern(banks[heldBank]->patterns[level],false);needPattern=false;
   freeSlots.push(heldBank);hasHeldBank=false;
   if(sample==phraseStart)emit({sample,bar,-1,3,1,0,true});
  }
  // A seek invalidates future phrase ownership. Wait for the main producer to
  // replenish a bank without playing the previous pattern or advancing events.
  if(needPattern){std::fill_n(outLeft+done,frames-done,0);std::fill_n(outRight+done,frames-done,0);return;}
  uint64_t beatSample=uint64_t(std::llround(nextBeat*spb));
  if(sample>=beatSample){emit({beatSample,nextBeat/4,-1,(nextBeat%4==0)?2:1,1,double(nextBeat%4),nextBeat%4==0});++nextBeat;beatSample=uint64_t(std::llround(nextBeat*spb));}
  auto interlude=interludeRequest.load(std::memory_order_acquire);
  if(interlude!=UINT64_MAX && sample>=(interlude>>2)){interludeAt=interlude>>2;activeCueKind=int(interlude&3);emit({interludeAt,bar,10,4,1,double(beat%4),true});interludeRequest.compare_exchange_strong(interlude,UINT64_MAX,std::memory_order_acq_rel);}
  uint64_t nextPhrase=uint64_t(std::llround((bar/theme.phraseBars+1)*theme.phraseBars*4*spb));
  int count=std::min({frames-done,512,int(std::min(beatSample,nextPhrase)-sample)});
  if(count<=0)count=1;
  engine->process(left.data(),right.data(),count);
  for(int i=0;i<count;++i){
   // Slow gain startup/re-entry and DC rejection; limiter responds sample exactly.
   outputGain+=float(1/(rate*.018))*(theme.masterGain-outputGain);
   float l=left[i],r=right[i];
   // Continuous low-level tonic/fifth pad makes breaths intentional and keeps
   // arrangement releases from becoming digital silence. Its phase is a pure
   // function of the shared integer timeline, including after joining late.
   const double time=(sample+i)/rate,tonic=440*std::exp2((36+theme.key-69)/12.);
   const float pad=float(std::sin(time*tonic*2*std::numbers::pi)+.32*std::sin(time*tonic*1.5*2*std::numbers::pi))*.009f*theme.padLevel;
   l+=pad;r+=pad;
   if(interludeAt!=UINT64_MAX){double age=(sample+i-interludeAt)/rate;if(age<.9){int midi=(activeCueKind==2?60:activeCueKind==3?36:48)+theme.key;double hz=440*std::exp2((midi-69)/12.);float cue=float(std::sin(age*hz*2*std::numbers::pi))*float(std::exp(-age*6))*float(std::min(1.,age*300))*.05f;l+=cue;r+=cue;}else interludeAt=UINT64_MAX;}
   dcLeft+=.0003f*(l-dcLeft);dcRight+=.0003f*(r-dcRight);const int level=actualIntensity.load(std::memory_order_relaxed);
   const float levelGain=level==0?.60f:level==1?.64f:level==2?.90f:1.f;
   arrangementGain+=.006f*(levelGain-arrangementGain);
   l=(l-dcLeft)*outputGain*arrangementGain*5.0f;r=(r-dcRight)*outputGain*arrangementGain*5.0f;
   float peak=std::max(std::abs(l),std::abs(r));float needed=peak>.60f?.60f/peak:1;
   limiterGain=needed<limiterGain?needed:limiterGain+.00008f*(1-limiterGain);
   outLeft[done+i]=l*limiterGain*postGain;outRight[done+i]=r*limiterGain*postGain;
  }
  mixed.store(sample+count,std::memory_order_release);done+=count;
 }
}
}
