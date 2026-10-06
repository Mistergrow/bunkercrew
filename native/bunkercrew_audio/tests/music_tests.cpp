#include "live_music.h"
#include <fstream>
#include <iostream>
#include <vector>
#include <chrono>
#include <unordered_set>
#include <cstdlib>
#include <new>
#include <cstring>
#include <sstream>
#include <limits>
#include <thread>
static thread_local bool realtime=false;
static std::atomic<uint64_t> rtAllocations{0};
void *operator new(std::size_t n){if(realtime)++rtAllocations;if(auto p=std::malloc(n?n:1))return p;throw std::bad_alloc();}
void *operator new(std::size_t n,const std::nothrow_t&) noexcept {try{return ::operator new(n);}catch(...){return nullptr;}}
void *operator new[](std::size_t n){return ::operator new(n);}
void *operator new[](std::size_t n,const std::nothrow_t& tag) noexcept {return ::operator new(n,tag);}
void operator delete(void *p) noexcept {std::free(p);}
void operator delete(void *p,std::size_t) noexcept {std::free(p);}
void operator delete(void *p,const std::nothrow_t&) noexcept {std::free(p);}
void operator delete[](void *p) noexcept {std::free(p);}
void operator delete[](void *p,std::size_t) noexcept {std::free(p);}
void operator delete[](void *p,const std::nothrow_t&) noexcept {std::free(p);}
using namespace bunkercrew;
static int checks=0;
static void check(bool value,const char *name){++checks;if(!value){std::cerr<<"FAIL "<<name<<"\n";std::exit(1);}}
static uint64_t hash_pattern(const tessel::Pattern &p){uint64_t h=1469598103934665603ull;for(auto &e:p.events){const unsigned char *bytes=reinterpret_cast<const unsigned char*>(&e.beatPosition);for(unsigned i=0;i<sizeof(double);++i)h=(h^bytes[i])*1099511628211ull;h=(h^uint64_t(e.instrument))*1099511628211ull;h=(h^uint64_t(e.note))*1099511628211ull;h=(h^uint64_t(e.velocity*100000))*1099511628211ull;}return h;}
static void wave_header(std::ofstream &f,uint32_t count,uint32_t rate){uint32_t bytes=count*4,chunk=36+bytes,fmt=16,byteRate=rate*4;uint16_t pcm=1,ch=2,align=4,bits=16;f.write("RIFF",4);f.write((char*)&chunk,4);f.write("WAVEfmt ",8);f.write((char*)&fmt,4);f.write((char*)&pcm,2);f.write((char*)&ch,2);f.write((char*)&rate,4);f.write((char*)&byteRate,4);f.write((char*)&align,2);f.write((char*)&bits,2);f.write("data",4);f.write((char*)&bytes,4);}
int main(int argc,char **argv){
 double seconds=40;int themeCount=1;std::string output;bool full=false,customized=false;int fixedIntensity=-1,sessionWaves=0;Theme selected;
 for(int i=1;i<argc;++i){std::string a=argv[i];if(a=="--hours"&&i+1<argc){seconds=std::stod(argv[++i])*3600;full=true;}else if(a=="--seconds"&&i+1<argc)seconds=std::stod(argv[++i]);else if(a=="--themes"&&i+1<argc)themeCount=std::stoi(argv[++i]);else if(a=="--wav"&&i+1<argc)output=argv[++i];else if(a=="--intensity"&&i+1<argc)fixedIntensity=std::clamp(std::stoi(argv[++i]),0,3);else if(a=="--session-waves"&&i+1<argc){sessionWaves=std::max(1,std::stoi(argv[++i]));seconds=sessionWaves*32.;}
 else if(i+1<argc){const std::string value=argv[++i];customized=true;
 if(a=="--composition-version")selected.compositionVersion=std::stoi(value);else if(a=="--score-form")selected.scoreForm=std::stoi(value);else if(a=="--melody")selected.melodyLevel=std::stof(value);else if(a=="--seed")selected.seed=uint32_t(std::stoull(value));else if(a=="--bpm")selected.bpm=std::stod(value);
 else if(a=="--key")selected.key=std::stoi(value);else if(a=="--genre")selected.genre=std::stoi(value);else if(a=="--scale")selected.scale=std::stoi(value);
 else if(a=="--personality")selected.personality=std::stoi(value);else if(a=="--kick")selected.kickSound=std::stoi(value);
 else if(a=="--phrase-bars")selected.phraseBars=std::stoi(value);else if(a=="--rest-every")selected.restEvery=std::stoi(value);
 else if(a=="--tone")selected.tone=std::stof(value);else if(a=="--punch")selected.punch=std::stof(value);
 else if(a=="--dust")selected.dust=std::stof(value);else if(a=="--swing")selected.swing=std::stof(value);
 else if(a=="--bass")selected.bassWeight=std::stof(value);else if(a=="--pad")selected.padLevel=std::stof(value);
 else if(a=="--room")selected.room=std::stof(value);else if(a=="--effects")selected.effects=std::stof(value);
 else if(a=="--density")selected.density=std::stof(value);else if(a=="--variation")selected.phraseVariation=std::stof(value);else if(a=="--normalization-db")selected.normalizationDb=std::stof(value);
 else if(a=="--motif"){std::istringstream values(value);std::string cell;int n=0;while(std::getline(values,cell,',')&&n<8)selected.motif[n++]=std::stoi(cell);}
 else{std::cerr<<"Unknown argument "<<a<<"\n";return 2;}
 }}
 // Malformed external settings are sanitized before touching the mixer.
 {Theme broken;broken.bpm=std::numeric_limits<double>::quiet_NaN();broken.tone=std::numeric_limits<float>::infinity();broken.kickSound=99;broken.scale=99;auto music=std::make_unique<LiveMusic>();music->configure(broken,48000);music->start();std::array<float,512> x{},y{};music->process(x.data(),y.data(),512);check(std::all_of(x.begin(),x.end(),[](float v){return std::isfinite(v);}),"malformed settings cannot corrupt audio");}
 // Genre contract: carried intro, then a stable 4/4 groove and short bass cell.
 for(int level=0;level<4;++level){Theme t;auto p=LiveMusic::compose(t,0,level);int kicks=0,stabs=0;for(auto &e:p.events){if(e.instrument==0){++kicks;if(level>0)check(e.beatPosition==std::floor(e.beatPosition),"groove kicks sit on integer quarter beats");}if(e.instrument==tessel::melodyTrack){++stabs;check(level<=1?e.duration>4:e.duration<.2,"intro carries notes while attacks use short stabs");}if(e.instrument==tessel::bassTrack&&level>0)check(e.duration<=.2,"groove bass is short and offbeat");}check(level==0?kicks<p.settings.bars:kicks==p.settings.bars*4,"four-on-the-floor starts after the cinematic stage");check(p.settings.cinematicMelody==(level<=1),"cinematic synth mode matches arrangement stage");}
 // Genres use different groove structures rather than only different names.
 std::unordered_set<uint64_t> genrePatterns;
 for(int genre=0;genre<4;++genre){Theme t;t.genre=genre;auto pattern=LiveMusic::compose(t,0,3);genrePatterns.insert(hash_pattern(pattern));int kicks=0,snares=0;for(auto &e:pattern.events){if(e.instrument==0){++kicks;if(genre<2)check(e.beatPosition==std::floor(e.beatPosition),"techno/schranz remain four-on-the-floor");}if(e.instrument==1)++snares;}check(genre<2?kicks==pattern.settings.bars*4:kicks<pattern.settings.bars*4,"hip-hop and breaks use broken kick grids");if(genre>=2)check(snares>=pattern.settings.bars*2,"hip-hop and breaks retain backbeat snare");}
 check(genrePatterns.size()==4,"four genuinely different instrumental genre patterns");
 // Refreshed scores keep authored melody, low-end separation and phrase relief.
 {Theme t;t.compositionVersion=2;t.bpm=130;t.key=2;t.restEvery=4;
  for(int level=0;level<4;++level){auto p=LiveMusic::compose(t,0,level);int kicks=0,melodies=0,basses=0;
   for(auto &e:p.events){if(e.instrument==0){++kicks;if(level>0)check(e.beatPosition==std::floor(e.beatPosition),"v2 anchors every real kick to the quarter beat");}
    if(e.instrument==tessel::bassTrack){++basses;check(e.note<36,"v2 sub stays below C2");if(level>0){check(std::fmod(e.beatPosition,1.)==.5,"v2 sub enters precisely between kicks");check(e.duration<=.18,"v2 sub gate leaves the next kick clear");}}
    if(e.instrument==tessel::melodyTrack){++melodies;check(level<=1?e.duration>=3:e.duration<=.2,"v2 motif carries in calm stages and rounds into combat stabs");}}
   check(level==0?kicks==2:kicks==32,"v2 only sparse intro removes drums from the quarter grid");
   check(level==0?basses==4:basses==32,"v2 groove owns real offbeat sub events");
   check(melodies>=7,"v2 question and answer remain audible throughout an authored phrase");
   check(p.settings.warmStab==(level>=2),"v2 combat uses rounded analogue tone instead of FM bells");
  }
  auto completePhrase=LiveMusic::compose(t,0,2),relief=LiveMusic::compose(t,3,2);
  check(relief.events.size()<completePhrase.events.size(),"v2 relief removes ornamentation but preserves the rhythm foundation");
  t.scoreForm=1;auto music=std::make_unique<LiveMusic>();music->configure(t,48000);music->start();
  std::array<float,512> x{},y{};const double phraseSamples=32*48000*60/t.bpm;
  constexpr int levels[4]={0,1,2,1};
  for(int phrase=0;phrase<4;++phrase){const uint64_t boundary=uint64_t(std::llround(phrase*phraseSamples));
   while(music->mixed_samples()<=boundary){music->prepare_phrases();music->process(x.data(),y.data(),int(std::min<uint64_t>(512,boundary+1-music->mixed_samples())));MusicEvent e;while(music->poll(e)){} }
   check(music->intensity()==levels[phrase],"v2 fixed menu form renders intro, build, drop and relief on actual phrase boundaries");
  }
 }
 // Current arrangement and pending future command are separate join state.
 {Theme join;join.bpm=120;join.initialIntensity=3;auto music=std::make_unique<LiveMusic>();music->configure(join,48000);
  check(music->intensity()==3,"join intensity is published before playback starts");
  music->request_intensity(0,6);music->start(3*4*24000);std::array<float,512> x{},y{};
  const uint64_t boundary=8*4*24000;
  while(music->mixed_samples()<boundary){music->prepare_phrases();int n=music->mixed_samples()==0?512:int(std::min<uint64_t>(512,boundary-music->mixed_samples()));music->process(x.data(),y.data(),n);
   check(music->intensity()==3,"pending quiet phrase never replaces a joining combat stage early");MusicEvent e;while(music->poll(e)){} }
  music->prepare_phrases();music->process(x.data(),y.data(),1);
  check(music->intensity()==0,"pending join command adopts at the next complete phrase");
 }
 // A rewind/restart never reuses a future phrase or its already queued events.
 {Theme t;t.bpm=120;t.compositionVersion=2;t.scoreForm=1;
  auto music=std::make_unique<LiveMusic>();music->configure(t,48000);music->start();
  std::array<float,512> x{},y{};
  auto mix=[&](int n=512){realtime=true;music->process(x.data(),y.data(),n);realtime=false;};
  mix();
  check(music->mixed_samples()==512 && std::any_of(x.begin(),x.end(),[](float v){return std::abs(v)>1e-7f;}),"normal first start uses its already prepared intro without a silent block");
  auto reposition=[&](uint64_t target,int level){
   music->seek(target);mix();
   check(music->mixed_samples()==target,"seek waits at the target sample until a matching generation is composed");
   check(music->intensity()==level,"seek resolves the arrangement from its target phrase rather than the previous drop");
   check(std::all_of(x.begin(),x.end(),[](float v){return v==0;}),"waiting for seek composition produces no obsolete audio");
   MusicEvent event;check(!music->poll(event),"seek excludes queued trigger events from the old transport generation");
   music->prepare_phrases();mix();
   check(music->mixed_samples()==target+512,"composition resumes from the exact seek position");
   check(music->intensity()==level,"the resumed bank has the intended target arrangement");
  };
  reposition(16*4*24000,2);
  MusicEvent event;bool dropKick=false;while(music->poll(event))if(event.track==0 && event.sample==16*4*24000 && event.strength>.7f)dropKick=true;
  check(dropKick,"forward seek produces a real drop kick at its exact sample");
  music->prepare_phrases();mix(); // Leave new-generation events queued deliberately.
  reposition(0,0);
  bool introKick=false;while(music->poll(event))if(event.track==0 && event.sample==0 && event.strength<.35f)introKick=true;
  check(introKick,"rewind produces the authored quiet intro kick rather than a future full-strength kick");
  reposition(9*4*24000+257,1);
  bool oldHit=false;while(music->poll(event))oldHit|=event.sample<9*4*24000+257;
  check(!oldHit,"mid-phrase rewind cannot emit a trigger preceding its new position");
  music->stop();music->start();mix();
  check(music->mixed_samples()==0 && music->intensity()==0,"restarting the same core resets the intro and waits for its correct phrase");
  music->prepare_phrases();mix();
  introKick=false;while(music->poll(event))if(event.track==0 && event.sample==0 && event.strength<.35f)introKick=true;
  check(introKick,"same-core restart generates its real sample-zero intro trigger");
  reposition(56*4*24000,1);
  music->prepare_phrases();mix();
  check(std::any_of(x.begin(),x.end(),[](float v){return std::abs(v)>1e-6f;}),"a far-forward seek resumes actual audible synthesis");
 }
 // Rewinding an adaptive score restores the initial bank before a future command.
 {Theme t;t.bpm=120;t.initialIntensity=3;auto music=std::make_unique<LiveMusic>();music->configure(t,48000);music->request_intensity(0,8);music->start();
  std::array<float,512> x{},y{};auto mix=[&](int n=512){realtime=true;music->process(x.data(),y.data(),n);realtime=false;};
  mix();check(music->intensity()==3,"adaptive opening preserves its actual join bank before the future command");
  music->seek(8*4*24000);mix();music->prepare_phrases();mix();check(music->intensity()==0,"forward seek applies an already reached intensity command");
  music->seek(3*4*24000);mix();music->prepare_phrases();mix();check(music->intensity()==3,"rewind before an intensity command restores initial arrangement instead of keeping its future level");
  music->request_intensity(2,0);music->seek(0);mix();music->prepare_phrases();mix();check(music->intensity()==2,"an explicit sample-zero intensity command survives a rewind");
 }
 // Two real threads retain SPSC ownership while controls repeatedly seek.
 {Theme t;t.bpm=120;t.compositionVersion=2;auto music=std::make_unique<LiveMusic>();music->configure(t,48000);music->start();
  std::atomic<unsigned> requested{0},completed{0};std::atomic<bool> finite{true};
  std::thread consumer([&](){std::array<float,512> x{},y{};for(unsigned cycle=1;cycle<=128;++cycle){
   while(requested.load(std::memory_order_acquire)<cycle)std::this_thread::yield();
   for(int block=0;block<4;++block){realtime=true;music->process(x.data(),y.data(),512);realtime=false;for(float v:x)if(!std::isfinite(v))finite=false;for(float v:y)if(!std::isfinite(v))finite=false;}
   completed.store(cycle,std::memory_order_release);
  }});
  for(unsigned cycle=1;cycle<=128;++cycle){music->request_intensity(int(cycle%4),0);music->seek(uint64_t(cycle%19)*4*24000+cycle*17);requested.store(cycle,std::memory_order_release);
   while(completed.load(std::memory_order_acquire)<cycle){music->prepare_phrases();MusicEvent event;while(music->poll(event)){}std::this_thread::yield();}
  }
  consumer.join();check(finite.load(),"concurrent producer/composer and audio seek consumer emit only finite samples");
  std::array<float,512> x{},y{};music->seek(0);realtime=true;music->process(x.data(),y.data(),512);realtime=false;music->prepare_phrases();realtime=true;music->process(x.data(),y.data(),512);realtime=false;
  check(music->mixed_samples()==512 && music->intensity()==0,"banks remain reusable after concurrent repeated seeks without losing slots");
  check(rtAllocations==0,"all seek, restart and concurrent audio callbacks remain allocation free");
 }
 // Exact trigger positions and tail behavior of the supplied engine itself.
 auto engine=std::make_unique<tessel::DrumEngine>();engine->prepare(48000);
 tessel::Pattern p;p.settings.bpm=120;p.settings.bars=4;p.settings.effects=.8f;p.settings.fx[5]=.6f;p.events.push_back({0,0,.8f});p.events.push_back({1,1,.7f});
 auto snapshot=std::make_unique<tessel::Snapshot>(tessel::compile(p));engine->setPattern(*snapshot);
 std::array<float,512> l{},r{};engine->process(l.data(),r.data(),512);
 tessel::Pattern empty=p;empty.events.clear();auto silent=std::make_unique<tessel::Snapshot>(tessel::compile(empty));engine->setPattern(*silent);
 engine->process(l.data(),r.data(),512);check(engine->mixedSamples()==1024,"pattern change preserves sample clock");
 check(std::any_of(l.begin(),l.end(),[](float x){return std::abs(x)>1e-5f;}),"pending change retains playing voices and effect tails");
 for(int i=0;i<186;++i)engine->process(l.data(),r.data(),512);
 check(engine->mixedSamples()>96000,"bar quantization continues transport");
 Theme reese;reese.hookStyle=1;auto a=std::make_unique<LiveMusic>(),b=std::make_unique<LiveMusic>();a->configure(reese,48000);b->configure(reese,48000);a->start();b->start();
 std::array<float,512> l2{},r2{};
 for(int j=0;j<200;++j){a->prepare_phrases();b->prepare_phrases();realtime=true;a->process(l.data(),r.data(),512);b->process(l2.data(),r2.data(),512);realtime=false;check(std::memcmp(l.data(),l2.data(),sizeof(l))==0&&std::memcmp(r.data(),r2.data(),sizeof(r))==0,"identical seed yields bit-identical local audio");}
 check(rtAllocations==0,"mixer has no operator-new allocation");
 MusicEvent event;uint64_t last=0;int kicks=0;while(a->poll(event)){if(event.kind==1||event.kind==2)check(event.sample==uint64_t(std::llround((event.bar*4+event.beat)*48000*60/reese.bpm)),"clock event exact rounded sample");if(event.track==0){++kicks;check(event.sample>=last,"hit event chronological");last=event.sample;}}
 check(kicks>0,"native engine emits real drum events");
 uint64_t total=0;double sum=0;float peak=0,jump=0,prior=0;uint64_t zeroRuns=0,longestZero=0;uint64_t allHash=1469598103934665603ull,eventHash=1469598103934665603ull;
 auto begin=std::chrono::steady_clock::now();
 std::ofstream wav;if(!output.empty()){wav.open(output,std::ios::binary);wave_header(wav,uint32_t(seconds*48000),48000);}
 for(int index=0;index<themeCount;++index){
  Theme t;t.seed=0x574152u+index*997;t.bpm=78+index*3;t.key=(9+index*2)%12;t.personality=index%8;t.tone=.28f+index*.025f;t.phraseBars=index%3==0?16:8;t.hookStyle=index%4==0?1:0;t.genre=index%4;t.bpm=(t.genre==0?114:t.genre==1?144:t.genre==2?88:128)+index%5;
  if(customized)t=selected;
  std::unordered_set<uint64_t> phrases;for(unsigned n=0;n<64;++n)phrases.insert(hash_pattern(LiveMusic::compose(t,n,n%4)));check(phrases.size()>60,"phrase arrangements avoid repeated identical loops");auto tuningPattern=LiveMusic::compose(t,0,2);check(tuningPattern.voices[tessel::bassTrack].pitch==1.f&&tuningPattern.voices[tessel::melodyTrack].pitch==1.f,"tonal voices retain theme tuning");
  auto music=std::make_unique<LiveMusic>();music->configure(t,48000);if(fixedIntensity>=0)music->request_intensity(fixedIntensity,0);music->start();
  const uint64_t totalTarget=uint64_t(std::llround(seconds*48000));
  uint64_t target=totalTarget/themeCount+(uint64_t(index)<totalTarget%themeCount?1:0),made=0,change=0;
  while(made<target){int n=int(std::min<uint64_t>(512,target-made));if(made>=change && fixedIntensity<0){int level=int((made/uint64_t(48000*25))%4);
   if(sessionWaves){double timeline=made/48000.;int wave=int(timeline/32)+1;double phase=std::fmod(timeline,32.);level=phase<8?(wave>=12?1:0):phase<12?2:phase<28?((wave%5==0||wave>=10)?3:2):0;}uint64_t bar=uint64_t(music->mixed_samples()/(48000*60/t.bpm*4));music->request_intensity(level,(bar/t.phraseBars+1)*t.phraseBars);change=made+48000*(sessionWaves?1:25);}music->prepare_phrases();realtime=true;music->process(l.data(),r.data(),n);realtime=false;
   for(int i=0;i<n;++i){check(std::isfinite(l[i])&&std::isfinite(r[i]),"finite audio");sum+=(l[i]*l[i]+r[i]*r[i])*.5;peak=std::max({peak,std::abs(l[i]),std::abs(r[i])});jump=std::max(jump,std::abs(l[i]-prior));prior=l[i];if(std::abs(l[i])+std::abs(r[i])<1e-8){++zeroRuns;longestZero=std::max(longestZero,zeroRuns);}else zeroRuns=0;uint32_t bits;std::memcpy(&bits,&l[i],4);allHash=(allHash^bits)*1099511628211ull;if(wav){int16_t sl=int16_t(std::clamp(l[i],-1.f,1.f)*32767),sr=int16_t(std::clamp(r[i],-1.f,1.f)*32767);wav.write((char*)&sl,2);wav.write((char*)&sr,2);}}
   while(music->poll(event)){eventHash=(eventHash^event.sample)*1099511628211ull;eventHash=(eventHash^uint64_t(event.track+1))*1099511628211ull;eventHash=(eventHash^uint64_t(event.kind))*1099511628211ull;eventHash=(eventHash^uint64_t(event.strength*100000))*1099511628211ull;}made+=n;total+=n;
  }
  check(music->mixed_samples()==target,"continuous integer sample transport");check(music->dropped_events()==0,"bounded event delivery without overflow");
 }
 check(rtAllocations==0,"long-run mixer allocation free");check(peak<=.881f,"limiter peak bound");check(longestZero<24000,"no half-second silent dropouts");
 double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
 std::cout<<"{\"checks\":"<<checks<<",\"samples\":"<<total<<",\"audio_seconds\":"<<double(total)/48000<<",\"render_seconds\":"<<elapsed<<",\"realtime_allocations\":"<<rtAllocations<<",\"rms_dbfs\":"<<20*std::log10(std::sqrt(sum/total))<<",\"peak\":"<<peak<<",\"max_sample_jump\":"<<jump<<",\"max_zero_run\":"<<longestZero<<",\"hash\":"<<allHash<<",\"event_hash\":"<<eventHash<<",\"full_endurance\":"<<(full?"true":"false")<<"}\n";
}
