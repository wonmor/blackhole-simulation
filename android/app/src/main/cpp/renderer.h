// Vulkan multipass renderer for the Kerr black-hole simulation.
//
// Mirrors the macOS/iOS Metal renderer (apple/.../Renderer.swift):
//   1. scene  -> sceneRT     (HDR rgba16f, fullscreen-triangle raymarcher)
//   2. taa    -> history[i]   (neighborhood-clamped temporal AA)
//   3. bright -> bloomBright  (luminance threshold, half-res)
//   4. blurH  -> bloomScratch
//   5. blurV  -> bloomBright
//   6. comp   -> swapchain    (additive bloom + ACES + gamma)
//
// Single frame-in-flight: we wait on the previous frame's fence before reusing
// the shared offscreen targets. The workload is GPU-bound (heavy ray loop), so
// the lost CPU/GPU overlap costs little and keeps resource lifetimes trivially
// correct.
#pragma once

#include <vulkan/vulkan.h>
#include <android/native_window.h>

#include <array>
#include <cstdint>
#include <map>
#include <mutex>
#include <vector>

// Uniform block — byte-for-byte identical to the GLSL std140 block in
// shaders/common.glsl (no vec3/array members, so tight packing == std140).
struct BHUniforms {
    float   resolution[2];        // 0
    float   time;                 // 8
    float   mass;                 // 12
    float   spin;                 // 16
    float   diskDensity;          // 20
    float   diskTemp;             // 24
    float   zoom;                 // 28
    float   mouse[2];             // 32
    float   lensingStrength;      // 40
    float   diskSize;             // 44
    int32_t maxRaySteps;          // 48
    int32_t enableDoppler;        // 52
    int32_t enableJets;           // 56
    int32_t enableLensing;        // 60
    int32_t enableDisk;           // 64
    int32_t enableStars;          // 68
    int32_t enablePhotonGlow;     // 72
    int32_t enableRedshiftView;   // 76
    float   jitter[2];            // 80
    float   diskScaleHeight;      // 88
    float   bloomThreshold;       // 92
    float   bloomIntensity;       // 96
    float   taaFeedback;          // 100
    float   frameDragStrength;    // 104
    int32_t frameIndex;           // 108 -> 112
};
static_assert(sizeof(BHUniforms) == 112, "BHUniforms must match GLSL std140 block");

// Target state pushed from the UI thread. Read once per frame under lock.
struct InputState {
    float mass = 1.0f, spin = 0.5f, lensingStrength = 0.7f, frameDragStrength = 2.0f;
    float diskDensity = 4.0f, diskTemp = 9500.0f, diskSize = 50.0f, diskScaleHeight = 0.2f;
    float bloomThreshold = 1.0f, bloomIntensity = 0.45f, autoSpin = 0.005f;
    float targetYaw = 0.5f, targetPitch = 0.539f, targetZoom = 100.0f;
    float renderScale = 1.0f;
    int   maxRaySteps = 128;
    uint8_t flagsMask = 0b0011111;   // lensing|disk|doppler|photon|stars (jets/redshift off)
    bool  taaEnabled = true;
    bool  bloomEnabled = true;
    double lastInteraction = 0.0;    // CLOCK_MONOTONIC seconds
    bool  paused = false;
};

struct Telemetry {
    float fps = 0.0f;
    float frameTimeMs = 0.0f;
    float effectiveScale = 1.0f;
};

// A render target: image + memory + view + framebuffer.
struct RenderTarget {
    VkImage        image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView    view = VK_NULL_HANDLE;
    VkFramebuffer  framebuffer = VK_NULL_HANDLE;
    uint32_t       width = 0, height = 0;
};

class Renderer {
public:
    bool init(ANativeWindow* window);
    void resize(int width, int height);
    void drawFrame();
    void shutdown();

    void setParams(const InputState& s);
    void setCamera(float yaw, float pitch, float zoom);
    void setPaused(bool paused);
    Telemetry telemetry();

    bool valid() const { return device_ != VK_NULL_HANDLE; }

private:
    // ---- setup ----
    bool createInstance();
    bool createSurface(ANativeWindow* window);
    bool pickPhysicalDevice();
    bool createDevice();
    bool createSwapchain();
    void destroySwapchain();
    bool createRenderPasses();
    bool createSamplerAndDummy();
    bool createUniformBuffer();
    bool createDescriptorInfra();
    bool createPostPipelines();
    VkPipeline scenePipeline(uint8_t mask);     // cached, specialization per flag mask
    bool createOffscreenTargets(uint32_t w, uint32_t h, float scale);
    void destroyOffscreenTargets();

    // ---- helpers ----
    uint32_t findMemoryType(uint32_t typeBits, VkMemoryPropertyFlags props);
    bool makeTarget(RenderTarget& rt, uint32_t w, uint32_t h, VkRenderPass rp);
    void destroyTarget(RenderTarget& rt);
    VkShaderModule loadModule(const char* name);
    VkPipeline buildPipeline(VkShaderModule vert, VkShaderModule frag,
                             VkRenderPass rp,
                             const VkSpecializationInfo* spec);
    void recordPass(VkCommandBuffer cb, VkRenderPass rp, VkFramebuffer fb,
                    uint32_t w, uint32_t h, VkPipeline pipe,
                    VkImageView tex0, VkImageView tex1, uint32_t setIndex);
    BHUniforms buildUniforms(const InputState& s, double now);
    void updateDynamicScale(double dt, const InputState& s);
    static float haltonAt(int index, int base);

    // ---- Vulkan core ----
    VkInstance        instance_ = VK_NULL_HANDLE;
    VkSurfaceKHR      surface_ = VK_NULL_HANDLE;
    VkPhysicalDevice  phys_ = VK_NULL_HANDLE;
    VkDevice          device_ = VK_NULL_HANDLE;
    uint32_t          queueFamily_ = 0;
    VkQueue           queue_ = VK_NULL_HANDLE;

    VkSwapchainKHR    swapchain_ = VK_NULL_HANDLE;
    VkFormat          swapFormat_ = VK_FORMAT_UNDEFINED;
    VkExtent2D        swapExtent_{};
    std::vector<VkImage>       swapImages_;
    std::vector<VkImageView>   swapViews_;
    std::vector<VkFramebuffer> swapFramebuffers_;

    static constexpr VkFormat kHdrFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
    VkRenderPass rpOffscreen_ = VK_NULL_HANDLE;   // rgba16f, finalLayout = SHADER_READ
    VkRenderPass rpSwap_ = VK_NULL_HANDLE;        // swapchain, finalLayout = PRESENT

    // Offscreen targets
    RenderTarget sceneRT_{};
    RenderTarget history_[2]{};
    RenderTarget bloomBright_{};
    RenderTarget bloomScratch_{};
    int  historyIdx_ = 0;
    bool historyValid_ = false;

    // Pipelines
    VkDescriptorSetLayout dsLayout_ = VK_NULL_HANDLE;
    VkPipelineLayout      pipelineLayout_ = VK_NULL_HANDLE;
    std::map<uint8_t, VkPipeline> scenePipelines_;
    VkPipeline taaPipe_ = VK_NULL_HANDLE;
    VkPipeline brightPipe_ = VK_NULL_HANDLE;
    VkPipeline blurHPipe_ = VK_NULL_HANDLE;
    VkPipeline blurVPipe_ = VK_NULL_HANDLE;
    VkPipeline copyPipe_ = VK_NULL_HANDLE;
    VkPipeline compositePipe_ = VK_NULL_HANDLE;

    VkShaderModule smBlackholeVert_ = VK_NULL_HANDLE;
    VkShaderModule smBlackholeFrag_ = VK_NULL_HANDLE;
    VkShaderModule smPostVert_ = VK_NULL_HANDLE;

    // Per-frame resources (single in-flight)
    VkCommandPool   cmdPool_ = VK_NULL_HANDLE;
    VkCommandBuffer cmd_ = VK_NULL_HANDLE;
    VkSemaphore     semImageAvailable_ = VK_NULL_HANDLE;
    VkSemaphore     semRenderFinished_ = VK_NULL_HANDLE;
    VkFence         fence_ = VK_NULL_HANDLE;

    VkBuffer        uboBuffer_ = VK_NULL_HANDLE;
    VkDeviceMemory  uboMemory_ = VK_NULL_HANDLE;
    void*           uboMapped_ = nullptr;

    static constexpr uint32_t kNumDescriptorSets = 6;  // scene, taa, bright, blurH, blurV, composite
    VkDescriptorPool descPool_ = VK_NULL_HANDLE;
    std::array<VkDescriptorSet, kNumDescriptorSets> descSets_{};

    VkSampler    sampler_ = VK_NULL_HANDLE;
    RenderTarget dummy_{};   // 1x1 sampled by passes that don't need a 2nd input

    // State
    std::mutex   stateMutex_;
    InputState   pending_{};
    Telemetry    telemetry_{};

    bool   needSwapRecreate_ = false;
    uint32_t pendingW_ = 0, pendingH_ = 0;

    // Frame timing / camera smoothing / adaptive resolution (ported from Swift)
    double startTime_ = 0.0;
    double lastFrameTime_ = 0.0;
    int32_t frameIndex_ = 0;
    double smoothedFPS_ = 0.0;

    float displayedYaw_ = 0.5f, displayedPitch_ = 0.539f, displayedZoom_ = 100.0f;
    float internalYaw_ = 0.5f;     // auto-spin advances this
    bool  cameraInitialized_ = false;
    const float cameraDamping_ = 12.0f;

    float dynamicScale_ = 1.0f;
    double pidIntegral_ = 0.0, pidPrevError_ = 0.0;
    const double pidKp_ = 0.025, pidKi_ = 0.005, pidKd_ = 0.04;
    const double pidTargetFPS_ = 60.0, pidDeadzoneFPS_ = 5.0;
    const float dynamicScaleMin_ = 0.5f, dynamicScaleMax_ = 1.0f;
    float rtScale_ = 1.0f;          // scale used to allocate current targets

    BHUniforms lastUniforms_{};
};
