#pragma once
#include "live_music.h"
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
namespace godot {
class TesselPlayback : public AudioStreamPlayback {
 GDCLASS(TesselPlayback,AudioStreamPlayback)
 std::shared_ptr<bunkercrew::LiveMusic> core;
 std::array<float,512> left{},right{};
protected:static void _bind_methods();
public:
 TesselPlayback();
 void attach(std::shared_ptr<bunkercrew::LiveMusic> value){core=std::move(value);}
 void _start(double from_pos) override;
 void _stop() override;
 bool _is_playing() const override;
 double _get_playback_position() const override;
 void _seek(double position) override;
 int32_t _mix(AudioFrame *buffer,float rate_scale,int32_t frames) override;
 void set_intensity(int32_t level);
 void request_intensity_at_bar(int32_t level,int64_t bar);
 void request_interlude(const String &kind,int64_t sample);
 void seek_samples(int64_t sample);
 Array poll_events(int32_t max_events=256);
 int64_t mixed_samples() const;
 int32_t current_intensity() const;
 double bpm() const;
 int32_t beats_per_bar() const{return 4;}
 int32_t mix_rate() const;
 Dictionary metadata() const;
};
class TesselStream : public AudioStream {
 GDCLASS(TesselStream,AudioStream)
 mutable std::shared_ptr<bunkercrew::LiveMusic> core;
 bunkercrew::Theme theme;
 int64_t pending_seek=0;
protected:static void _bind_methods();
public:
 TesselStream();
 Ref<AudioStreamPlayback> _instantiate_playback() const override;
 String _get_stream_name() const override{return "Bunkercrew live Tessel";}
 double _get_length() const override{return 0;}
 bool _is_monophonic() const override{return true;}
 double _get_bpm() const override{return theme.bpm;}
 int32_t _get_bar_beats() const override{return 4;}
 bool _has_loop() const override{return true;}
 void set_theme(int64_t seed,const Dictionary &settings);
 void set_intensity(int32_t level);
 void request_intensity_at_bar(int32_t level,int64_t bar);
 void request_interlude(const String &kind,int64_t sample);
 void seek_samples(int64_t sample);
 Array poll_events(int32_t max_events=256);
 int64_t mixed_samples() const;
 int32_t current_intensity() const;
 double bpm() const{return theme.bpm;}
 int32_t beats_per_bar() const{return 4;}
 int32_t mix_rate() const;
 Dictionary metadata() const;
 PackedFloat32Array render_offline(int32_t frames); // main-thread validation only
};
}
