#include "tessel_stream.h"
#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/core/class_db.hpp>
namespace godot {
static Array poll(const std::shared_ptr<bunkercrew::LiveMusic> &core,int max_events){
 Array list;if(!core)return list;core->prepare_phrases();bunkercrew::MusicEvent e;
 const char *kinds[]={"hit","beat","bar","phrase","interlude"};
 for(int n=0;n<std::clamp(max_events,0,1024)&&core->poll(e);++n){Dictionary d;d["sample"]=int64_t(e.sample);d["track"]=e.track;d["strength"]=e.strength;d["bar"]=int64_t(e.bar);d["beat"]=e.beat;d["accent"]=e.accent;d["kind"]=kinds[std::clamp(e.kind,0,4)];list.push_back(d);}return list;
}
static Dictionary state(const std::shared_ptr<bunkercrew::LiveMusic> &core){Dictionary d;if(core){d["seed"]=int64_t(core->seed());d["playing"]=core->playing();d["mixed_samples"]=int64_t(core->mixed_samples());d["mix_rate"]=core->sample_rate();d["bpm"]=core->bpm();d["beats_per_bar"]=4;d["phrase_bars"]=core->phrase_bars();d["intensity"]=core->intensity();d["genre"]=core->genre();d["dropped_events"]=int64_t(core->dropped_events());d["engine"]="tessel-native-2";d["composition_version"]=core->composition_version();d["score_form"]=core->score_form();}return d;}
static void intensity(const std::shared_ptr<bunkercrew::LiveMusic> &core,int level){if(core){auto bar=uint64_t(core->mixed_samples()/(core->sample_rate()*60/core->bpm()*4));core->request_intensity(level,(bar/core->phrase_bars()+1)*core->phrase_bars());}}
static int cue(const String &kind){return kind=="victory"?2:kind=="loss"||kind=="defeat"?3:1;}
#define BIND_COMMON(C) \
 ClassDB::bind_method(D_METHOD("set_intensity","level"),&C::set_intensity); \
 ClassDB::bind_method(D_METHOD("request_intensity_at_bar","level","bar"),&C::request_intensity_at_bar); \
 ClassDB::bind_method(D_METHOD("request_interlude","kind","sample"),&C::request_interlude); \
 ClassDB::bind_method(D_METHOD("seek_samples","sample"),&C::seek_samples); \
 ClassDB::bind_method(D_METHOD("poll_events","max_events"),&C::poll_events,DEFVAL(256)); \
 ClassDB::bind_method(D_METHOD("mixed_samples"),&C::mixed_samples); \
 ClassDB::bind_method(D_METHOD("current_intensity"),&C::current_intensity); \
 ClassDB::bind_method(D_METHOD("bpm"),&C::bpm); \
 ClassDB::bind_method(D_METHOD("beats_per_bar"),&C::beats_per_bar); \
 ClassDB::bind_method(D_METHOD("mix_rate"),&C::mix_rate); \
 ClassDB::bind_method(D_METHOD("metadata"),&C::metadata)
void TesselPlayback::_bind_methods(){BIND_COMMON(TesselPlayback);}
void TesselStream::_bind_methods(){BIND_COMMON(TesselStream);ClassDB::bind_method(D_METHOD("set_theme","seed","settings"),&TesselStream::set_theme);ClassDB::bind_method(D_METHOD("render_offline","frames"),&TesselStream::render_offline);}
TesselPlayback::TesselPlayback()=default;
TesselStream::TesselStream():core(std::make_shared<bunkercrew::LiveMusic>()) {core->configure(theme,AudioServer::get_singleton()->get_mix_rate());}
Ref<AudioStreamPlayback> TesselStream::_instantiate_playback() const{Ref<TesselPlayback> playback;playback.instantiate();playback->attach(core);return playback;}
void TesselStream::set_theme(int64_t seed,const Dictionary &s){
 theme.seed=uint32_t(seed);
 theme.initialIntensity=0;theme.compositionVersion=1;theme.scoreForm=0;
 #define NUMBER(name,field) if(s.has(name) && (s[name].get_type()==Variant::INT || s[name].get_type()==Variant::FLOAT))theme.field=s[name]
 NUMBER("bpm",bpm);NUMBER("key",key);NUMBER("scale",scale);NUMBER("personality",personality);NUMBER("kick_sound",kickSound);NUMBER("hook_style",hookStyle);NUMBER("phrase_bars",phraseBars);NUMBER("genre",genre);NUMBER("initial_intensity",initialIntensity);NUMBER("composition_version",compositionVersion);NUMBER("score_form",scoreForm);NUMBER("tone",tone);NUMBER("brightness",tone);NUMBER("punch",punch);NUMBER("swing",swing);NUMBER("dust",dust);NUMBER("effects",effects);NUMBER("bass_weight",bassWeight);NUMBER("melody_level",melodyLevel);NUMBER("pad_level",padLevel);NUMBER("room",room);NUMBER("density",density);NUMBER("rest_every",restEvery);NUMBER("phrase_variation",phraseVariation);NUMBER("master_gain",masterGain);NUMBER("normalization_db",normalizationDb);
 #undef NUMBER
 if(s.has("motif") && s["motif"].get_type()==Variant::ARRAY){Array motif=s["motif"];for(int i=0;i<std::min(8,int(motif.size()));++i)theme.motif[i]=int(motif[i]);}
 // A theme is immutable for a session. Replacing a playing stream takes effect on
 // its next playback; existing playback retains its shared, immutable engine.
 core=std::make_shared<bunkercrew::LiveMusic>();core->configure(theme,AudioServer::get_singleton()->get_mix_rate());theme.bpm=core->bpm();theme.phraseBars=core->phrase_bars();
}
void TesselPlayback::_start(double from_pos){if(core)core->start(uint64_t(std::max(0.,from_pos)*core->sample_rate()));}
void TesselPlayback::_stop(){if(core)core->stop();}
bool TesselPlayback::_is_playing() const{return core&&core->playing();}
double TesselPlayback::_get_playback_position() const{return core?core->mixed_samples()/core->sample_rate():0;}
void TesselPlayback::_seek(double pos){if(core)core->seek(uint64_t(std::max(0.,pos)*core->sample_rate()));}
int32_t TesselPlayback::_mix(AudioFrame *buffer,float,int32_t frames){
 if(!core)return 0;
 for(int done=0;done<frames;){int n=std::min(512,frames-done);core->process(left.data(),right.data(),n);for(int i=0;i<n;++i){buffer[done+i].left=left[i];buffer[done+i].right=right[i];}done+=n;}
 return frames;
}
void TesselPlayback::set_intensity(int32_t level){intensity(core,level);}
void TesselStream::set_intensity(int32_t level){intensity(core,level);}
void TesselPlayback::request_intensity_at_bar(int32_t level,int64_t bar){if(core)core->request_intensity(level,uint64_t(std::max<int64_t>(0,bar)));}
void TesselStream::request_intensity_at_bar(int32_t level,int64_t bar){if(core)core->request_intensity(level,uint64_t(std::max<int64_t>(0,bar)));}
void TesselPlayback::request_interlude(const String &kind,int64_t sample){if(core)core->request_interlude(cue(kind),uint64_t(std::max<int64_t>(0,sample)));}
void TesselStream::request_interlude(const String &kind,int64_t sample){if(core)core->request_interlude(cue(kind),uint64_t(std::max<int64_t>(0,sample)));}
void TesselPlayback::seek_samples(int64_t sample){if(core)core->seek(uint64_t(std::max<int64_t>(0,sample)));}
void TesselStream::seek_samples(int64_t sample){pending_seek=std::max<int64_t>(0,sample);if(core)core->seek(uint64_t(pending_seek));}
Array TesselPlayback::poll_events(int32_t max_events){return poll(core,max_events);}
Array TesselStream::poll_events(int32_t max_events){return poll(core,max_events);}
int64_t TesselPlayback::mixed_samples() const{return core?int64_t(core->mixed_samples()):0;}
int64_t TesselStream::mixed_samples() const{return core?int64_t(core->mixed_samples()):0;}
int32_t TesselPlayback::current_intensity() const{return core?core->intensity():0;}
int32_t TesselStream::current_intensity() const{return core?core->intensity():0;}
double TesselPlayback::bpm() const{return core?core->bpm():0;}
int32_t TesselPlayback::mix_rate() const{return core?int32_t(core->sample_rate()):48000;}
int32_t TesselStream::mix_rate() const{return core?int32_t(core->sample_rate()):48000;}
Dictionary TesselPlayback::metadata() const{return state(core);}
Dictionary TesselStream::metadata() const{return state(core);}
PackedFloat32Array TesselStream::render_offline(int32_t frames){
 PackedFloat32Array output;frames=std::clamp(frames,0,48000*60);if(core->playing())return output;output.resize(frames*2);std::array<float,512> l{},r{};core->start(uint64_t(pending_seek));for(int done=0;done<frames;){core->prepare_phrases();int n=std::min(512,frames-done);core->process(l.data(),r.data(),n);for(int i=0;i<n;++i){output.set((done+i)*2,l[i]);output.set((done+i)*2+1,r[i]);}done+=n;}core->stop();return output;
}
}
