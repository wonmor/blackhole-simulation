#include "shaders.h"
#include <cstring>

// Each *.inc is produced by `glslc -mfmt=c` and is a brace-wrapped list of
// 32-bit words, so it slots directly into a uint32_t[] initializer.
namespace {
const uint32_t k_blackhole_vert[] =
#include "blackhole.vert.inc"
;
const uint32_t k_blackhole_frag[] =
#include "blackhole.frag.inc"
;
const uint32_t k_post_vert[] =
#include "post.vert.inc"
;
const uint32_t k_taa_frag[] =
#include "taa.frag.inc"
;
const uint32_t k_bright_frag[] =
#include "bright.frag.inc"
;
const uint32_t k_blur_frag[] =
#include "blur.frag.inc"
;
const uint32_t k_composite_frag[] =
#include "composite.frag.inc"
;
const uint32_t k_copy_frag[] =
#include "copy.frag.inc"
;
const uint32_t k_accum_frag[] =
#include "accum.frag.inc"
;

struct Entry { const char* name; const uint32_t* data; size_t bytes; };
const Entry kTable[] = {
    {"blackhole.vert", k_blackhole_vert, sizeof(k_blackhole_vert)},
    {"blackhole.frag", k_blackhole_frag, sizeof(k_blackhole_frag)},
    {"post.vert",      k_post_vert,      sizeof(k_post_vert)},
    {"taa.frag",       k_taa_frag,       sizeof(k_taa_frag)},
    {"bright.frag",    k_bright_frag,    sizeof(k_bright_frag)},
    {"blur.frag",      k_blur_frag,      sizeof(k_blur_frag)},
    {"composite.frag", k_composite_frag, sizeof(k_composite_frag)},
    {"copy.frag",      k_copy_frag,      sizeof(k_copy_frag)},
    {"accum.frag",     k_accum_frag,     sizeof(k_accum_frag)},
};
}  // namespace

bool getSpirv(const char* name, const uint32_t** data, size_t* sizeBytes) {
    for (const auto& e : kTable) {
        if (std::strcmp(e.name, name) == 0) {
            *data = e.data;
            *sizeBytes = e.bytes;
            return true;
        }
    }
    return false;
}
