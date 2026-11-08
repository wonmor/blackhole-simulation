cmake_minimum_required(VERSION 3.22.1)
project(blackhole LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GLSLC_BIN and RUST_LIBS_DIR are passed from app/build.gradle.kts.
if(NOT DEFINED GLSLC_BIN)
    message(FATAL_ERROR "GLSLC_BIN not set (expected from Gradle).")
endif()
if(NOT DEFINED RUST_LIBS_DIR)
    message(FATAL_ERROR "RUST_LIBS_DIR not set (expected from Gradle).")
endif()

# ---------------------------------------------------------------------------
# Compile GLSL -> SPIR-V, emitting each as a C initializer list (-mfmt=c) that
# shaders.cpp #includes directly. No runtime asset loading required.
# ---------------------------------------------------------------------------
set(SHADER_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shaders)
set(SHADER_GEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/gen_shaders)
file(MAKE_DIRECTORY ${SHADER_GEN_DIR})

set(SHADERS
    blackhole.vert blackhole.frag
    post.vert taa.frag bright.frag blur.frag composite.frag copy.frag accum.frag)

set(SHADER_INCS "")
foreach(s ${SHADERS})
    add_custom_command(
        OUTPUT ${SHADER_GEN_DIR}/${s}.inc
        COMMAND ${GLSLC_BIN} --target-env=vulkan1.1 -O -mfmt=c
                ${SHADER_SRC_DIR}/${s} -o ${SHADER_GEN_DIR}/${s}.inc
        DEPENDS ${SHADER_SRC_DIR}/${s} ${SHADER_SRC_DIR}/common.glsl
        COMMENT "glslc ${s} -> ${s}.inc"
        VERBATIM)
    list(APPEND SHADER_INCS ${SHADER_GEN_DIR}/${s}.inc)
endforeach()
add_custom_target(gen_shaders DEPENDS ${SHADER_INCS})

# ---------------------------------------------------------------------------
# Rust gravitas-ffi static archive (staged per-ABI by the cargo Gradle task).
# ---------------------------------------------------------------------------
set(GRAVITAS_LIB ${RUST_LIBS_DIR}/${ANDROID_ABI}/libgravitas_ffi.a)
add_library(gravitas_ffi STATIC IMPORTED)
set_target_properties(gravitas_ffi PROPERTIES IMPORTED_LOCATION ${GRAVITAS_LIB})

# ---------------------------------------------------------------------------
# Native library
# ---------------------------------------------------------------------------
add_library(blackhole SHARED
    native-lib.cpp
    renderer.cpp
    shaders.cpp
    gravitas_jni.cpp
    yuv.cpp)

add_dependencies(blackhole gen_shaders)
target_include_directories(blackhole PRIVATE ${SHADER_GEN_DIR} ${CMAKE_CURRENT_SOURCE_DIR})

find_library(log-lib log)
find_library(android-lib android)
find_library(vulkan-lib vulkan)

target_link_libraries(blackhole
    gravitas_ffi
    ${vulkan-lib}
    ${android-lib}
    ${log-lib})
