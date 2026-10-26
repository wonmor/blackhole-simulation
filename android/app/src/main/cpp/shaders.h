// Access to SPIR-V modules embedded at build time (see CMakeLists.txt — glslc
// emits each shader as a C initializer list that we compile straight in).
#pragma once
#include <cstddef>
#include <cstdint>

// Returns true and fills data/sizeBytes for a known shader name
// (e.g. "blackhole.frag"). sizeBytes is the byte length of the SPIR-V blob.
bool getSpirv(const char* name, const uint32_t** data, size_t* sizeBytes);
