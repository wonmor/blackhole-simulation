#include "renderer.h"
#include "shaders.h"

#include <android/log.h>
#include <vulkan/vulkan_android.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <ctime>

#define LOG_TAG "BlackHoleVk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define VK_CHECK(x)                                                              \
    do {                                                                        \
        VkResult _e = (x);                                                      \
        if (_e != VK_SUCCESS) LOGE("VK error %d at %s:%d", _e, __FILE__, __LINE__); \
    } while (0)

namespace {
double nowSeconds() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}
float wrap01(float x) {
    x = fmodf(x, 1.0f);
    if (x < 0.0f) x += 1.0f;
    return x;
}
float clampf(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
}  // namespace

// Defined below; used by createSwapchain().
static VkRenderPass makeRenderPass(VkDevice dev, VkFormat fmt, VkImageLayout finalLayout);

// ===========================================================================
// Setup
// ===========================================================================

bool Renderer::init(ANativeWindow* window) {
    startTime_ = nowSeconds();
    lastFrameTime_ = startTime_;
    {
        std::lock_guard<std::mutex> lk(stateMutex_);
        displayedZoom_ = pending_.targetZoom;
        displayedPitch_ = pending_.targetPitch;
        displayedYaw_ = pending_.targetYaw;
    }
    if (!createInstance()) return false;
    if (!createSurface(window)) return false;
    if (!pickPhysicalDevice()) return false;
    if (!createDevice()) return false;
    if (!createRenderPasses()) return false;
    if (!createSwapchain()) return false;
    if (!createSamplerAndDummy()) return false;
    if (!createUniformBuffer()) return false;
    if (!createDescriptorInfra()) return false;
    if (!createPostPipelines()) return false;

    float scale = clampf(pending_.renderScale, dynamicScaleMin_, dynamicScaleMax_);
    if (!createOffscreenTargets(swapExtent_.width, swapExtent_.height, scale)) return false;

    // Per-frame objects (single in-flight)
    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pci.queueFamilyIndex = queueFamily_;
    VK_CHECK(vkCreateCommandPool(device_, &pci, nullptr, &cmdPool_));

    VkCommandBufferAllocateInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cbi.commandPool = cmdPool_;
    cbi.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbi.commandBufferCount = 1;
    VK_CHECK(vkAllocateCommandBuffers(device_, &cbi, &cmd_));

    VkSemaphoreCreateInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    VK_CHECK(vkCreateSemaphore(device_, &si, nullptr, &semImageAvailable_));
    VkFenceCreateInfo fi{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    fi.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    VK_CHECK(vkCreateFence(device_, &fi, nullptr, &fence_));

    LOGI("Renderer initialised (%ux%u)", swapExtent_.width, swapExtent_.height);
    return true;
}

bool Renderer::createInstance() {
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "BlackHole";
    app.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    app.pEngineName = "gravitas";
    app.apiVersion = VK_API_VERSION_1_1;

    const char* exts[] = {VK_KHR_SURFACE_EXTENSION_NAME,
                          VK_KHR_ANDROID_SURFACE_EXTENSION_NAME};
    VkInstanceCreateInfo ci{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ci.pApplicationInfo = &app;
    ci.enabledExtensionCount = 2;
    ci.ppEnabledExtensionNames = exts;
    VkResult r = vkCreateInstance(&ci, nullptr, &instance_);
    if (r != VK_SUCCESS) { LOGE("vkCreateInstance failed %d", r); return false; }
    return true;
}

bool Renderer::createSurface(ANativeWindow* window) {
    VkAndroidSurfaceCreateInfoKHR ci{VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR};
    ci.window = window;
    return vkCreateAndroidSurfaceKHR(instance_, &ci, nullptr, &surface_) == VK_SUCCESS;
}

bool Renderer::pickPhysicalDevice() {
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(instance_, &n, nullptr);
    if (n == 0) { LOGE("No Vulkan devices"); return false; }
    std::vector<VkPhysicalDevice> devs(n);
    vkEnumeratePhysicalDevices(instance_, &n, devs.data());

    for (auto d : devs) {
        uint32_t qn = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(d, &qn, nullptr);
        std::vector<VkQueueFamilyProperties> q(qn);
        vkGetPhysicalDeviceQueueFamilyProperties(d, &qn, q.data());
        for (uint32_t i = 0; i < qn; ++i) {
            VkBool32 present = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(d, i, surface_, &present);
            if ((q[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && present) {
                phys_ = d;
                queueFamily_ = i;
                VkPhysicalDeviceProperties props;
                vkGetPhysicalDeviceProperties(d, &props);
                LOGI("GPU: %s", props.deviceName);
                return true;
            }
        }
    }
    LOGE("No graphics+present queue family");
    return false;
}

bool Renderer::createDevice() {
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qi{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qi.queueFamilyIndex = queueFamily_;
    qi.queueCount = 1;
    qi.pQueuePriorities = &prio;

    const char* exts[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkDeviceCreateInfo ci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    ci.queueCreateInfoCount = 1;
    ci.pQueueCreateInfos = &qi;
    ci.enabledExtensionCount = 1;
    ci.ppEnabledExtensionNames = exts;
    if (vkCreateDevice(phys_, &ci, nullptr, &device_) != VK_SUCCESS) {
        LOGE("vkCreateDevice failed");
        return false;
    }
    vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);
    return true;
}

bool Renderer::createSwapchain() {
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys_, surface_, &caps);

    uint32_t fn = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(phys_, surface_, &fn, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(fn);
    vkGetPhysicalDeviceSurfaceFormatsKHR(phys_, surface_, &fn, formats.data());

    // The composite pass already encodes gamma, so present a UNORM (non-sRGB)
    // surface to avoid a double gamma.
    VkSurfaceFormatKHR chosen = formats[0];
    for (auto f : formats) {
        if (f.format == VK_FORMAT_R8G8B8A8_UNORM ||
            f.format == VK_FORMAT_B8G8R8A8_UNORM) { chosen = f; break; }
    }
    swapFormat_ = chosen.format;

    // The swapchain render pass attachment format must match the chosen surface
    // format, which is only known here — build it now (stable across recreate).
    if (rpSwap_ == VK_NULL_HANDLE) {
        rpSwap_ = makeRenderPass(device_, swapFormat_, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    }

    VkExtent2D extent = caps.currentExtent;
    if (extent.width == 0xFFFFFFFF) {
        extent.width = pendingW_ ? pendingW_ : 1080;
        extent.height = pendingH_ ? pendingH_ : 1920;
    }
    extent.width = std::max(caps.minImageExtent.width,
                            std::min(caps.maxImageExtent.width, extent.width));
    extent.height = std::max(caps.minImageExtent.height,
                             std::min(caps.maxImageExtent.height, extent.height));
    swapExtent_ = extent;

    uint32_t imageCount = caps.minImageCount + 1;
    if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount)
        imageCount = caps.maxImageCount;

    VkSwapchainCreateInfoKHR ci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    ci.surface = surface_;
    ci.minImageCount = imageCount;
    ci.imageFormat = swapFormat_;
    ci.imageColorSpace = chosen.colorSpace;
    ci.imageExtent = swapExtent_;
    ci.imageArrayLayers = 1;
    ci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ci.preTransform = caps.currentTransform;
    ci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    ci.presentMode = VK_PRESENT_MODE_FIFO_KHR;   // always supported
    ci.clipped = VK_TRUE;
    if (vkCreateSwapchainKHR(device_, &ci, nullptr, &swapchain_) != VK_SUCCESS) {
        LOGE("vkCreateSwapchainKHR failed");
        return false;
    }

    uint32_t sc = 0;
    vkGetSwapchainImagesKHR(device_, swapchain_, &sc, nullptr);
    swapImages_.resize(sc);
    vkGetSwapchainImagesKHR(device_, swapchain_, &sc, swapImages_.data());

    swapViews_.resize(sc);
    // One render-finished semaphore per swapchain image: a single shared one
    // can be re-signalled while the presentation engine still waits on it.
    semRenderFinished_.assign(sc, VK_NULL_HANDLE);
    for (uint32_t i = 0; i < sc; ++i) {
        VkSemaphoreCreateInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VK_CHECK(vkCreateSemaphore(device_, &si, nullptr, &semRenderFinished_[i]));
    }
    swapFramebuffers_.resize(sc);
    for (uint32_t i = 0; i < sc; ++i) {
        VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        vi.image = swapImages_[i];
        vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
        vi.format = swapFormat_;
        vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        VK_CHECK(vkCreateImageView(device_, &vi, nullptr, &swapViews_[i]));

        VkFramebufferCreateInfo fi{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
        fi.renderPass = rpSwap_;
        fi.attachmentCount = 1;
        fi.pAttachments = &swapViews_[i];
        fi.width = swapExtent_.width;
        fi.height = swapExtent_.height;
        fi.layers = 1;
        VK_CHECK(vkCreateFramebuffer(device_, &fi, nullptr, &swapFramebuffers_[i]));
    }
    return true;
}

void Renderer::destroySwapchain() {
    for (auto fb : swapFramebuffers_) if (fb) vkDestroyFramebuffer(device_, fb, nullptr);
    for (auto v : swapViews_) if (v) vkDestroyImageView(device_, v, nullptr);
    swapFramebuffers_.clear();
    swapViews_.clear();
    swapImages_.clear();
    for (auto sem : semRenderFinished_) if (sem) vkDestroySemaphore(device_, sem, nullptr);
    semRenderFinished_.clear();
    if (swapchain_) { vkDestroySwapchainKHR(device_, swapchain_, nullptr); swapchain_ = VK_NULL_HANDLE; }
}

static VkRenderPass makeRenderPass(VkDevice dev, VkFormat fmt, VkImageLayout finalLayout) {
    VkAttachmentDescription att{};
    att.format = fmt;
    att.samples = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    att.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    att.finalLayout = finalLayout;

    VkAttachmentReference ref{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription sub{};
    sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount = 1;
    sub.pColorAttachments = &ref;

    VkSubpassDependency deps[2]{};
    deps[0].srcSubpass = VK_SUBPASS_EXTERNAL;
    deps[0].dstSubpass = 0;
    // Source scope must include COLOR_ATTACHMENT_OUTPUT: that is the stage the
    // swapchain-acquire semaphore waits at, and the UNDEFINED -> attachment
    // layout transition has to happen after it. With FRAGMENT_SHADER alone the
    // transition can run while the presentation engine still reads the image,
    // which showed up as flicker on Mali/PowerVR phones (Play review, HNELN2-Q1).
    deps[0].srcStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT |
                           VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    deps[0].dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    deps[0].srcAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    deps[0].dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    deps[1].srcSubpass = 0;
    deps[1].dstSubpass = VK_SUBPASS_EXTERNAL;
    deps[1].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    deps[1].dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    deps[1].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    deps[1].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    VkRenderPassCreateInfo ci{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
    ci.attachmentCount = 1;
    ci.pAttachments = &att;
    ci.subpassCount = 1;
    ci.pSubpasses = &sub;
    ci.dependencyCount = 2;
    ci.pDependencies = deps;
    VkRenderPass rp = VK_NULL_HANDLE;
    vkCreateRenderPass(dev, &ci, nullptr, &rp);
    return rp;
}

bool Renderer::createRenderPasses() {
    // rpSwap_ is created inside createSwapchain() once the surface format is
    // chosen, so its attachment format matches the swapchain images.
    rpOffscreen_ = makeRenderPass(device_, kHdrFormat, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    return rpOffscreen_ != VK_NULL_HANDLE;
}

uint32_t Renderer::findMemoryType(uint32_t typeBits, VkMemoryPropertyFlags props) {
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(phys_, &mp);
    for (uint32_t i = 0; i < mp.memoryTypeCount; ++i) {
        if ((typeBits & (1u << i)) &&
            (mp.memoryTypes[i].propertyFlags & props) == props)
            return i;
    }
    return 0;
}

bool Renderer::makeTarget(RenderTarget& rt, uint32_t w, uint32_t h, VkRenderPass rp) {
    rt.width = w; rt.height = h;
    VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ii.imageType = VK_IMAGE_TYPE_2D;
    ii.format = kHdrFormat;
    ii.extent = {w, h, 1};
    ii.mipLevels = 1;
    ii.arrayLayers = 1;
    ii.samples = VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = VK_IMAGE_TILING_OPTIMAL;
    ii.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    if (vkCreateImage(device_, &ii, nullptr, &rt.image) != VK_SUCCESS) return false;

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(device_, rt.image, &mr);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize = mr.size;
    ai.memoryTypeIndex = findMemoryType(mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(device_, &ai, nullptr, &rt.memory) != VK_SUCCESS) return false;
    vkBindImageMemory(device_, rt.image, rt.memory, 0);

    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image = rt.image;
    vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vi.format = kHdrFormat;
    vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    if (vkCreateImageView(device_, &vi, nullptr, &rt.view) != VK_SUCCESS) return false;

    if (rp != VK_NULL_HANDLE) {
        VkFramebufferCreateInfo fi{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
        fi.renderPass = rp;
        fi.attachmentCount = 1;
        fi.pAttachments = &rt.view;
        fi.width = w; fi.height = h; fi.layers = 1;
        if (vkCreateFramebuffer(device_, &fi, nullptr, &rt.framebuffer) != VK_SUCCESS) return false;
    }
    return true;
}

void Renderer::destroyTarget(RenderTarget& rt) {
    if (rt.framebuffer) vkDestroyFramebuffer(device_, rt.framebuffer, nullptr);
    if (rt.view) vkDestroyImageView(device_, rt.view, nullptr);
    if (rt.image) vkDestroyImage(device_, rt.image, nullptr);
    if (rt.memory) vkFreeMemory(device_, rt.memory, nullptr);
    rt = RenderTarget{};
}

bool Renderer::createSamplerAndDummy() {
    VkSamplerCreateInfo si{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    si.magFilter = VK_FILTER_LINEAR;
    si.minFilter = VK_FILTER_LINEAR;
    si.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    si.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    VK_CHECK(vkCreateSampler(device_, &si, nullptr, &sampler_));

    // 1x1 dummy sampled by passes that don't bind a 2nd texture.
    if (!makeTarget(dummy_, 1, 1, VK_NULL_HANDLE)) return false;

    // Transition dummy UNDEFINED -> SHADER_READ_ONLY via a one-time submit.
    VkCommandBufferAllocateInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.queueFamilyIndex = queueFamily_;
    VkCommandPool tmpPool;
    vkCreateCommandPool(device_, &pci, nullptr, &tmpPool);
    cbi.commandPool = tmpPool;
    cbi.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbi.commandBufferCount = 1;
    VkCommandBuffer cb;
    vkAllocateCommandBuffers(device_, &cbi, &cb);
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cb, &bi);
    VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    b.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    b.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = dummy_.image;
    b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    b.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                         VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0,
                         0, nullptr, 0, nullptr, 1, &b);
    vkEndCommandBuffer(cb);
    VkSubmitInfo s{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    s.commandBufferCount = 1;
    s.pCommandBuffers = &cb;
    vkQueueSubmit(queue_, 1, &s, VK_NULL_HANDLE);
    vkQueueWaitIdle(queue_);
    vkDestroyCommandPool(device_, tmpPool, nullptr);
    return true;
}

bool Renderer::createUniformBuffer() {
    VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bi.size = sizeof(BHUniforms);
    bi.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    bi.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VK_CHECK(vkCreateBuffer(device_, &bi, nullptr, &uboBuffer_));

    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(device_, uboBuffer_, &mr);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize = mr.size;
    ai.memoryTypeIndex = findMemoryType(mr.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    VK_CHECK(vkAllocateMemory(device_, &ai, nullptr, &uboMemory_));
    vkBindBufferMemory(device_, uboBuffer_, uboMemory_, 0);
    vkMapMemory(device_, uboMemory_, 0, sizeof(BHUniforms), 0, &uboMapped_);
    return true;
}

bool Renderer::createDescriptorInfra() {
    VkDescriptorSetLayoutBinding b[3]{};
    b[0].binding = 0;
    b[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    b[0].descriptorCount = 1;
    b[0].stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    b[1].binding = 1;
    b[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    b[1].descriptorCount = 1;
    b[1].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    b[2].binding = 2;
    b[2].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    b[2].descriptorCount = 1;
    b[2].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;

    VkDescriptorSetLayoutCreateInfo li{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    li.bindingCount = 3;
    li.pBindings = b;
    VK_CHECK(vkCreateDescriptorSetLayout(device_, &li, nullptr, &dsLayout_));

    VkPipelineLayoutCreateInfo pli{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pli.setLayoutCount = 1;
    pli.pSetLayouts = &dsLayout_;
    VK_CHECK(vkCreatePipelineLayout(device_, &pli, nullptr, &pipelineLayout_));

    VkDescriptorPoolSize sizes[2]{};
    sizes[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    sizes[0].descriptorCount = kNumDescriptorSets;
    sizes[1].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    sizes[1].descriptorCount = kNumDescriptorSets * 2;
    VkDescriptorPoolCreateInfo dpi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    dpi.maxSets = kNumDescriptorSets;
    dpi.poolSizeCount = 2;
    dpi.pPoolSizes = sizes;
    VK_CHECK(vkCreateDescriptorPool(device_, &dpi, nullptr, &descPool_));

    std::array<VkDescriptorSetLayout, kNumDescriptorSets> layouts;
    layouts.fill(dsLayout_);
    VkDescriptorSetAllocateInfo dai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    dai.descriptorPool = descPool_;
    dai.descriptorSetCount = kNumDescriptorSets;
    dai.pSetLayouts = layouts.data();
    VK_CHECK(vkAllocateDescriptorSets(device_, &dai, descSets_.data()));
    return true;
}

VkShaderModule Renderer::loadModule(const char* name) {
    const uint32_t* data = nullptr;
    size_t bytes = 0;
    if (!getSpirv(name, &data, &bytes)) { LOGE("missing shader %s", name); return VK_NULL_HANDLE; }
    VkShaderModuleCreateInfo ci{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    ci.codeSize = bytes;
    ci.pCode = data;
    VkShaderModule m = VK_NULL_HANDLE;
    VK_CHECK(vkCreateShaderModule(device_, &ci, nullptr, &m));
    return m;
}

VkPipeline Renderer::buildPipeline(VkShaderModule vert, VkShaderModule frag,
                                   VkRenderPass rp, const VkSpecializationInfo* spec) {
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vert;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = frag;
    stages[1].pName = "main";
    stages[1].pSpecializationInfo = spec;

    VkPipelineVertexInputStateCreateInfo vin{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount = 1;
    vp.scissorCount = 1;

    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.cullMode = VK_CULL_MODE_NONE;
    rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth = 1.0f;

    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState cba{};
    cba.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                         VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    cba.blendEnable = VK_FALSE;
    VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount = 1;
    cb.pAttachments = &cba;

    VkDynamicState dyn[2] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    ds.dynamicStateCount = 2;
    ds.pDynamicStates = dyn;

    VkGraphicsPipelineCreateInfo ci{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    ci.stageCount = 2;
    ci.pStages = stages;
    ci.pVertexInputState = &vin;
    ci.pInputAssemblyState = &ia;
    ci.pViewportState = &vp;
    ci.pRasterizationState = &rs;
    ci.pMultisampleState = &ms;
    ci.pColorBlendState = &cb;
    ci.pDynamicState = &ds;
    ci.layout = pipelineLayout_;
    ci.renderPass = rp;
    ci.subpass = 0;
    VkPipeline pipe = VK_NULL_HANDLE;
    VK_CHECK(vkCreateGraphicsPipelines(device_, VK_NULL_HANDLE, 1, &ci, nullptr, &pipe));
    return pipe;
}

bool Renderer::createPostPipelines() {
    smBlackholeVert_ = loadModule("blackhole.vert");
    smBlackholeFrag_ = loadModule("blackhole.frag");
    smPostVert_ = loadModule("post.vert");
    VkShaderModule taa = loadModule("taa.frag");
    VkShaderModule bright = loadModule("bright.frag");
    VkShaderModule blur = loadModule("blur.frag");
    VkShaderModule comp = loadModule("composite.frag");
    VkShaderModule copy = loadModule("copy.frag");

    taaPipe_ = buildPipeline(smPostVert_, taa, rpOffscreen_, nullptr);
    brightPipe_ = buildPipeline(smPostVert_, bright, rpOffscreen_, nullptr);
    copyPipe_ = buildPipeline(smPostVert_, copy, rpOffscreen_, nullptr);
    compositePipe_ = buildPipeline(smPostVert_, comp, rpSwap_, nullptr);

    // blur direction via specialization constant id 0 (HORIZONTAL).
    VkSpecializationMapEntry me{0, 0, sizeof(VkBool32)};
    VkBool32 horiz = VK_TRUE, vert = VK_FALSE;
    VkSpecializationInfo specH{1, &me, sizeof(VkBool32), &horiz};
    VkSpecializationInfo specV{1, &me, sizeof(VkBool32), &vert};
    blurHPipe_ = buildPipeline(smPostVert_, blur, rpOffscreen_, &specH);
    blurVPipe_ = buildPipeline(smPostVert_, blur, rpOffscreen_, &specV);

    vkDestroyShaderModule(device_, taa, nullptr);
    vkDestroyShaderModule(device_, bright, nullptr);
    vkDestroyShaderModule(device_, blur, nullptr);
    vkDestroyShaderModule(device_, comp, nullptr);
    vkDestroyShaderModule(device_, copy, nullptr);
    return compositePipe_ != VK_NULL_HANDLE;
}

VkPipeline Renderer::scenePipeline(uint8_t mask) {
    auto it = scenePipelines_.find(mask);
    if (it != scenePipelines_.end()) return it->second;

    VkBool32 flags[7];
    VkSpecializationMapEntry entries[7];
    for (int i = 0; i < 7; ++i) {
        flags[i] = ((mask >> i) & 1) ? VK_TRUE : VK_FALSE;
        entries[i] = {(uint32_t)i, (uint32_t)(i * sizeof(VkBool32)), sizeof(VkBool32)};
    }
    VkSpecializationInfo spec{7, entries, sizeof(flags), flags};
    VkPipeline pipe = buildPipeline(smBlackholeVert_, smBlackholeFrag_, rpOffscreen_, &spec);
    scenePipelines_[mask] = pipe;
    return pipe;
}

bool Renderer::createOffscreenTargets(uint32_t w, uint32_t h, float scale) {
    destroyOffscreenTargets();
    rtScale_ = scale;
    uint32_t sw = std::max(1u, (uint32_t)(w * scale));
    uint32_t sh = std::max(1u, (uint32_t)(h * scale));
    bool ok = true;
    ok &= makeTarget(sceneRT_, sw, sh, rpOffscreen_);
    ok &= makeTarget(history_[0], sw, sh, rpOffscreen_);
    ok &= makeTarget(history_[1], sw, sh, rpOffscreen_);
    ok &= makeTarget(bloomBright_, std::max(1u, sw / 2), std::max(1u, sh / 2), rpOffscreen_);
    ok &= makeTarget(bloomScratch_, std::max(1u, sw / 2), std::max(1u, sh / 2), rpOffscreen_);
    historyValid_ = false;
    return ok;
}

void Renderer::destroyOffscreenTargets() {
    destroyTarget(sceneRT_);
    destroyTarget(history_[0]);
    destroyTarget(history_[1]);
    destroyTarget(bloomBright_);
    destroyTarget(bloomScratch_);
}

// ===========================================================================
// Per-frame
// ===========================================================================

float Renderer::haltonAt(int index, int base) {
    float f = 1.0f, r = 0.0f;
    int i = index;
    while (i > 0) { f /= base; r += f * (i % base); i /= base; }
    return r;
}

void Renderer::updateDynamicScale(double dt, const InputState& s) {
    double error = pidTargetFPS_ - smoothedFPS_;
    if (std::abs(error) <= pidDeadzoneFPS_) return;
    pidIntegral_ += error * dt;
    pidIntegral_ = std::min(std::max(pidIntegral_, -100.0), 100.0);
    double derivative = (error - pidPrevError_) / std::max(dt, 1e-3);
    pidPrevError_ = error;
    double correction = pidKp_ * error + pidKi_ * pidIntegral_ + pidKd_ * derivative;
    float next = (float)((double)dynamicScale_ - correction * 0.02);
    dynamicScale_ = clampf(next, dynamicScaleMin_, dynamicScaleMax_);

    // Reallocating the targets drops the TAA history, so every step is a
    // visible pop. Use coarse 0.1 steps and at most one change every 2 s, so a
    // GPU that hovers around the target can't ping-pong (seen as flicker).
    auto quantize = [](float x) { return std::round(x * 10.0f) / 10.0f; };
    float effective = clampf(quantize(dynamicScale_ * s.renderScale),
                             dynamicScaleMin_, dynamicScaleMax_);
    double now = lastFrameTime_;
    if (std::abs(effective - rtScale_) > 0.001f && now - lastScaleChange_ > 2.0) {
        lastScaleChange_ = now;
        createOffscreenTargets(swapExtent_.width, swapExtent_.height, effective);
    }
}

BHUniforms Renderer::buildUniforms(const InputState& s, double now) {
    BHUniforms u{};
    u.resolution[0] = (float)sceneRT_.width;
    u.resolution[1] = (float)sceneRT_.height;
    u.time = (float)(now - startTime_);
    u.mass = s.mass;
    u.spin = s.spin;
    u.diskDensity = s.diskDensity;
    u.diskTemp = s.diskTemp;
    u.zoom = displayedZoom_;
    u.mouse[0] = displayedYaw_;
    u.mouse[1] = displayedPitch_;
    u.lensingStrength = s.lensingStrength;
    u.diskSize = s.diskSize;
    u.maxRaySteps = s.maxRaySteps;
    u.enableDoppler = (s.flagsMask >> 2) & 1;
    u.enableJets = (s.flagsMask >> 5) & 1;
    u.enableLensing = (s.flagsMask >> 0) & 1;
    u.enableDisk = (s.flagsMask >> 1) & 1;
    u.enableStars = (s.flagsMask >> 4) & 1;
    u.enablePhotonGlow = (s.flagsMask >> 3) & 1;
    u.enableRedshiftView = (s.flagsMask >> 6) & 1;

    float h1 = haltonAt(frameIndex_ + 1, 2);
    float h2 = haltonAt(frameIndex_ + 1, 3);
    u.jitter[0] = (h1 - 0.5f) * 0.8f;
    u.jitter[1] = (h2 - 0.5f) * 0.8f;
    u.diskScaleHeight = s.diskScaleHeight;
    u.bloomThreshold = s.bloomThreshold;
    u.bloomIntensity = s.bloomIntensity;
    u.frameDragStrength = s.frameDragStrength;
    u.frameIndex = frameIndex_;
    u.diskTime = (float)diskTime_;
    u.taaFeedback = s.taaEnabled ? 0.92f : 0.0f;
    return u;
}

void Renderer::recordPass(VkCommandBuffer cb, VkRenderPass rp, VkFramebuffer fb,
                          uint32_t w, uint32_t h, VkPipeline pipe,
                          VkImageView tex0, VkImageView tex1, uint32_t setIndex) {
    VkDescriptorSet set = descSets_[setIndex];

    VkDescriptorBufferInfo bufInfo{uboBuffer_, 0, sizeof(BHUniforms)};
    VkDescriptorImageInfo img0{sampler_, tex0, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkDescriptorImageInfo img1{sampler_, tex1, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet w3[3]{};
    w3[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w3[0].dstSet = set; w3[0].dstBinding = 0; w3[0].descriptorCount = 1;
    w3[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    w3[0].pBufferInfo = &bufInfo;
    w3[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w3[1].dstSet = set; w3[1].dstBinding = 1; w3[1].descriptorCount = 1;
    w3[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    w3[1].pImageInfo = &img0;
    w3[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w3[2].dstSet = set; w3[2].dstBinding = 2; w3[2].descriptorCount = 1;
    w3[2].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    w3[2].pImageInfo = &img1;
    vkUpdateDescriptorSets(device_, 3, w3, 0, nullptr);

    VkClearValue clear{};
    clear.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
    VkRenderPassBeginInfo rpb{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
    rpb.renderPass = rp;
    rpb.framebuffer = fb;
    rpb.renderArea = {{0, 0}, {w, h}};
    rpb.clearValueCount = 1;
    rpb.pClearValues = &clear;
    vkCmdBeginRenderPass(cb, &rpb, VK_SUBPASS_CONTENTS_INLINE);

    VkViewport vpt{0.0f, 0.0f, (float)w, (float)h, 0.0f, 1.0f};
    VkRect2D sc{{0, 0}, {w, h}};
    vkCmdSetViewport(cb, 0, 1, &vpt);
    vkCmdSetScissor(cb, 0, 1, &sc);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout_,
                            0, 1, &set, 0, nullptr);
    vkCmdDraw(cb, 3, 1, 0, 0);
    vkCmdEndRenderPass(cb);
}

void Renderer::drawFrame() {
    if (!device_ || swapchain_ == VK_NULL_HANDLE) return;

    vkWaitForFences(device_, 1, &fence_, VK_TRUE, UINT64_MAX);

    if (needSwapRecreate_) {
        vkDeviceWaitIdle(device_);
        destroySwapchain();
        if (!createSwapchain()) return;
        createOffscreenTargets(swapExtent_.width, swapExtent_.height,
                               clampf(dynamicScale_ * pending_.renderScale,
                                      dynamicScaleMin_, dynamicScaleMax_));
        needSwapRecreate_ = false;
    }

    InputState s;
    {
        std::lock_guard<std::mutex> lk(stateMutex_);
        s = pending_;
    }
    if (s.paused) return;

    double now = nowSeconds();
    double dt = std::max(1.0 / 240.0, std::min(now - lastFrameTime_, 1.0 / 15.0));
    lastFrameTime_ = now;
    smoothedFPS_ = smoothedFPS_ * 0.92 + (1.0 / dt) * 0.08;
    diskTime_ += dt * (double)std::max(0.0f, s.diskSpeed);

    // Auto-spin: advance the persistent yaw target when idle.
    bool interacting = (now - s.lastInteraction) < 0.6;
    if (!interacting && std::abs(s.autoSpin) > 1e-5f) {
        float next = wrap01(s.targetYaw + (float)dt * s.autoSpin / (2.0f * (float)M_PI));
        s.targetYaw = next;
        std::lock_guard<std::mutex> lk(stateMutex_);
        pending_.targetYaw = next;   // persist so spin accumulates
    }

    // Camera smoothing (exponential blend toward targets).
    if (!cameraInitialized_) {
        displayedYaw_ = s.targetYaw;
        displayedPitch_ = s.targetPitch;
        displayedZoom_ = s.targetZoom;
        cameraInitialized_ = true;
    }
    float blend = 1.0f - std::exp(-cameraDamping_ * (float)dt);
    displayedPitch_ += (s.targetPitch - displayedPitch_) * blend;
    displayedZoom_ += (s.targetZoom - displayedZoom_) * blend;
    float dyaw = fmodf(s.targetYaw - displayedYaw_, 1.0f);
    if (dyaw > 0.5f) dyaw -= 1.0f;
    if (dyaw < -0.5f) dyaw += 1.0f;
    displayedYaw_ = wrap01(displayedYaw_ + dyaw * blend);

    if (smoothedFPS_ > 5) updateDynamicScale(dt, s);

    {
        std::lock_guard<std::mutex> lk(stateMutex_);
        telemetry_.fps = (float)smoothedFPS_;
        telemetry_.frameTimeMs = (float)(dt * 1000.0);
        telemetry_.effectiveScale = rtScale_;
    }

    // Acquire swapchain image.
    uint32_t imgIdx = 0;
    VkResult acq = vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX,
                                         semImageAvailable_, VK_NULL_HANDLE, &imgIdx);
    if (acq == VK_ERROR_OUT_OF_DATE_KHR) { needSwapRecreate_ = true; return; }

    // Build uniforms + history-reset detection.
    BHUniforms u = buildUniforms(s, now);
    bool camChanged = std::abs(lastUniforms_.mouse[0] - u.mouse[0]) > 0.005f ||
                      std::abs(lastUniforms_.mouse[1] - u.mouse[1]) > 0.005f ||
                      std::abs(lastUniforms_.zoom - u.zoom) > 0.05f;
    if (!historyValid_ || camChanged || !s.taaEnabled) u.taaFeedback = 0.0f;
    std::memcpy(uboMapped_, &u, sizeof(BHUniforms));
    lastUniforms_ = u;

    vkResetFences(device_, 1, &fence_);
    vkResetCommandBuffer(cmd_, 0);
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd_, &bi);

    // 1. Scene -> sceneRT (scene frag uses no samplers; bind dummy).
    recordPass(cmd_, rpOffscreen_, sceneRT_.framebuffer, sceneRT_.width, sceneRT_.height,
               scenePipeline(s.flagsMask), dummy_.view, dummy_.view, 0);

    // 2. TAA (or copy) -> history[cur]
    RenderTarget& resolved = history_[historyIdx_];
    RenderTarget& prev = history_[1 - historyIdx_];
    // Never sample a history target that has not been written yet (fresh
    // allocation after a resize or a dynamic-resolution step): copy instead.
    if (s.taaEnabled && historyValid_) {
        recordPass(cmd_, rpOffscreen_, resolved.framebuffer, resolved.width, resolved.height,
                   taaPipe_, sceneRT_.view, prev.view, 1);
    } else {
        recordPass(cmd_, rpOffscreen_, resolved.framebuffer, resolved.width, resolved.height,
                   copyPipe_, sceneRT_.view, dummy_.view, 1);
    }
    historyIdx_ = 1 - historyIdx_;
    historyValid_ = true;

    // 3-5. Bloom
    if (s.bloomEnabled) {
        recordPass(cmd_, rpOffscreen_, bloomBright_.framebuffer, bloomBright_.width, bloomBright_.height,
                   brightPipe_, resolved.view, dummy_.view, 2);
        recordPass(cmd_, rpOffscreen_, bloomScratch_.framebuffer, bloomScratch_.width, bloomScratch_.height,
                   blurHPipe_, bloomBright_.view, dummy_.view, 3);
        recordPass(cmd_, rpOffscreen_, bloomBright_.framebuffer, bloomBright_.width, bloomBright_.height,
                   blurVPipe_, bloomScratch_.view, dummy_.view, 4);
    }

    // 6. Composite -> swapchain
    recordPass(cmd_, rpSwap_, swapFramebuffers_[imgIdx], swapExtent_.width, swapExtent_.height,
               compositePipe_, resolved.view,
               s.bloomEnabled ? bloomBright_.view : sceneRT_.view, 5);

    vkEndCommandBuffer(cmd_);

    VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.waitSemaphoreCount = 1;
    submit.pWaitSemaphores = &semImageAvailable_;
    submit.pWaitDstStageMask = &waitStage;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &cmd_;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &semRenderFinished_[imgIdx];
    VK_CHECK(vkQueueSubmit(queue_, 1, &submit, fence_));

    VkPresentInfoKHR present{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present.waitSemaphoreCount = 1;
    present.pWaitSemaphores = &semRenderFinished_[imgIdx];
    present.swapchainCount = 1;
    present.pSwapchains = &swapchain_;
    present.pImageIndices = &imgIdx;
    VkResult pr = vkQueuePresentKHR(queue_, &present);
    if (pr == VK_ERROR_OUT_OF_DATE_KHR || pr == VK_SUBOPTIMAL_KHR) needSwapRecreate_ = true;

    frameIndex_++;
}

// ===========================================================================
// External state + lifecycle
// ===========================================================================

void Renderer::setParams(const InputState& s) {
    std::lock_guard<std::mutex> lk(stateMutex_);
    double keepInteraction = pending_.lastInteraction;
    float keepYaw = pending_.targetYaw, keepPitch = pending_.targetPitch, keepZoom = pending_.targetZoom;
    pending_ = s;
    // Camera is owned by setCamera()/auto-spin; don't let a params push stomp it.
    pending_.lastInteraction = keepInteraction;
    pending_.targetYaw = keepYaw;
    pending_.targetPitch = keepPitch;
    pending_.targetZoom = keepZoom;
}

void Renderer::setCamera(float yaw, float pitch, float zoom) {
    std::lock_guard<std::mutex> lk(stateMutex_);
    pending_.targetYaw = wrap01(yaw);
    pending_.targetPitch = clampf(pitch, 0.05f, 0.95f);
    pending_.targetZoom = clampf(zoom, 1.5f, 100.0f);
    pending_.lastInteraction = nowSeconds();
}

void Renderer::setPaused(bool paused) {
    std::lock_guard<std::mutex> lk(stateMutex_);
    pending_.paused = paused;
}

Telemetry Renderer::telemetry() {
    std::lock_guard<std::mutex> lk(stateMutex_);
    return telemetry_;
}

void Renderer::resize(int width, int height) {
    std::lock_guard<std::mutex> lk(stateMutex_);
    pendingW_ = (uint32_t)width;
    pendingH_ = (uint32_t)height;
    needSwapRecreate_ = true;
}

void Renderer::shutdown() {
    if (device_) vkDeviceWaitIdle(device_);

    destroyOffscreenTargets();
    destroyTarget(dummy_);

    for (auto& kv : scenePipelines_) vkDestroyPipeline(device_, kv.second, nullptr);
    scenePipelines_.clear();
    if (taaPipe_) vkDestroyPipeline(device_, taaPipe_, nullptr);
    if (brightPipe_) vkDestroyPipeline(device_, brightPipe_, nullptr);
    if (blurHPipe_) vkDestroyPipeline(device_, blurHPipe_, nullptr);
    if (blurVPipe_) vkDestroyPipeline(device_, blurVPipe_, nullptr);
    if (copyPipe_) vkDestroyPipeline(device_, copyPipe_, nullptr);
    if (compositePipe_) vkDestroyPipeline(device_, compositePipe_, nullptr);

    if (smBlackholeVert_) vkDestroyShaderModule(device_, smBlackholeVert_, nullptr);
    if (smBlackholeFrag_) vkDestroyShaderModule(device_, smBlackholeFrag_, nullptr);
    if (smPostVert_) vkDestroyShaderModule(device_, smPostVert_, nullptr);

    if (descPool_) vkDestroyDescriptorPool(device_, descPool_, nullptr);
    if (dsLayout_) vkDestroyDescriptorSetLayout(device_, dsLayout_, nullptr);
    if (pipelineLayout_) vkDestroyPipelineLayout(device_, pipelineLayout_, nullptr);

    if (uboMapped_) { vkUnmapMemory(device_, uboMemory_); uboMapped_ = nullptr; }
    if (uboBuffer_) vkDestroyBuffer(device_, uboBuffer_, nullptr);
    if (uboMemory_) vkFreeMemory(device_, uboMemory_, nullptr);

    if (sampler_) vkDestroySampler(device_, sampler_, nullptr);
    if (semImageAvailable_) vkDestroySemaphore(device_, semImageAvailable_, nullptr);
    if (fence_) vkDestroyFence(device_, fence_, nullptr);
    if (cmdPool_) vkDestroyCommandPool(device_, cmdPool_, nullptr);

    destroySwapchain();
    if (rpOffscreen_) vkDestroyRenderPass(device_, rpOffscreen_, nullptr);
    if (rpSwap_) vkDestroyRenderPass(device_, rpSwap_, nullptr);
    if (device_) { vkDestroyDevice(device_, nullptr); device_ = VK_NULL_HANDLE; }
    if (surface_) vkDestroySurfaceKHR(instance_, surface_, nullptr);
    if (instance_) vkDestroyInstance(instance_, nullptr);
    instance_ = VK_NULL_HANDLE;
}
