#ifndef BlackHole_Bridging_Header_h
#define BlackHole_Bridging_Header_h

#import "ShaderTypes.h"

// Pulled in only when the Gravitas xcframework is linked.
// The script at apple/scripts/build-gravitas-xcframework.sh produces it
// from physics-engine/gravitas-ffi.
#if __has_include(<gravitas.h>)
#  import <gravitas.h>
#  ifndef GRAVITAS_LINKED
#    define GRAVITAS_LINKED 1
#  endif
#endif

#endif
