#include "tessel_stream.h"
#include <godot_cpp/godot.hpp>
using namespace godot;
static void initialize(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE){GDREGISTER_CLASS(TesselStream);GDREGISTER_CLASS(TesselPlayback);}}
static void uninitialize(ModuleInitializationLevel){}
extern "C" {
GDExtensionBool GDE_EXPORT bunkercrew_audio_init(GDExtensionInterfaceGetProcAddress proc,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){GDExtensionBinding::InitObject init(proc,library,initialization);init.register_initializer(initialize);init.register_terminator(uninitialize);init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);return init.init();}
}
