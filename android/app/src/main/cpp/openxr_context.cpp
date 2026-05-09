#include "openxr_context.h"
#include <android/log.h>
#include <cstring>

#define LOG_TAG "TermisolVR"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace termisol {

bool OpenXrContext::Initialize(EGLDisplay display, EGLConfig config, EGLContext context) {
  if (!CreateInstance()) return false;

  XrSystemGetInfo system_info{XR_TYPE_SYSTEM_GET_INFO};
  system_info.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
  if (xrGetSystem(instance_, &system_info, &system_id_) != XR_SUCCESS) {
    ALOGE("xrGetSystem failed");
    return false;
  }

  if (!CreateSession(display, config, context)) return false;
  if (!CreateReferenceSpace()) return false;
  if (!CreateSwapchains()) return false;

  ALOGI("OpenXR initialized successfully");
  return true;
}

void OpenXrContext::Shutdown() {
  for (auto& sc : swapchains_) {
    if (sc.handle != XR_NULL_HANDLE) xrDestroySwapchain(sc.handle);
  }
  swapchains_.clear();
  if (reference_space_ != XR_NULL_HANDLE) xrDestroySpace(reference_space_);
  if (session_ != XR_NULL_HANDLE) xrDestroySession(session_);
  if (instance_ != XR_NULL_HANDLE) xrDestroyInstance(instance_);
}

bool OpenXrContext::CreateInstance() {
  XrApplicationInfo app_info{};
  strncpy(app_info.applicationName, "TermisolVR", XR_MAX_APPLICATION_NAME_SIZE - 1);
  app_info.applicationVersion = 1;
  app_info.apiVersion = XR_CURRENT_API_VERSION;

  const char* extensions[] = {XR_KHR_OPENGL_ES_ENABLE_EXTENSION_NAME};
  XrInstanceCreateInfo create_info{XR_TYPE_INSTANCE_CREATE_INFO};
  create_info.applicationInfo = app_info;
  create_info.enabledExtensionCount = 1;
  create_info.enabledExtensionNames = extensions;

  XrResult result = xrCreateInstance(&create_info, &instance_);
  if (XR_FAILED(result)) {
    ALOGE("xrCreateInstance failed: %d", result);
    return false;
  }
  return true;
}

bool OpenXrContext::CreateSession(EGLDisplay display, EGLConfig config, EGLContext context) {
  XrGraphicsBindingOpenGLESKHR graphics_binding{XR_TYPE_GRAPHICS_BINDING_OPENGL_ES_KHR};
  graphics_binding.display = display;
  graphics_binding.config = config;
  graphics_binding.context = context;

  XrSessionCreateInfo session_create_info{XR_TYPE_SESSION_CREATE_INFO};
  session_create_info.next = &graphics_binding;
  session_create_info.systemId = system_id_;

  if (xrCreateSession(instance_, &session_create_info, &session_) != XR_SUCCESS) {
    ALOGE("xrCreateSession failed");
    return false;
  }
  return true;
}

bool OpenXrContext::CreateReferenceSpace() {
  XrReferenceSpaceCreateInfo ref_space_create_info{XR_TYPE_REFERENCE_SPACE_CREATE_INFO};
  ref_space_create_info.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_LOCAL_FLOOR;
  ref_space_create_info.poseInReferenceSpace = {{0.0f, 0.0f, 0.0f, 1.0f}, {0.0f, 0.0f, 0.0f}};

  if (xrCreateReferenceSpace(session_, &ref_space_create_info, &reference_space_) != XR_SUCCESS) {
    ALOGE("xrCreateReferenceSpace failed");
    return false;
  }
  return true;
}

bool OpenXrContext::CreateSwapchains() {
  uint32_t view_count = 0;
  xrEnumerateViewConfigurationViews(instance_, system_id_, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                                    0, &view_count, nullptr);
  view_config_views_.resize(view_count, {XR_TYPE_VIEW_CONFIGURATION_VIEW});
  xrEnumerateViewConfigurationViews(instance_, system_id_, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                                    view_count, &view_count, view_config_views_.data());

  for (uint32_t i = 0; i < view_count; ++i) {
    const auto& config_view = view_config_views_[i];

    XrSwapchainCreateInfo swapchain_create_info{XR_TYPE_SWAPCHAIN_CREATE_INFO};
    swapchain_create_info.arraySize = 1;
    swapchain_create_info.format = GL_RGBA8;
    swapchain_create_info.width = config_view.recommendedImageRectWidth;
    swapchain_create_info.height = config_view.recommendedImageRectHeight;
    swapchain_create_info.mipCount = 1;
    swapchain_create_info.faceCount = 1;
    swapchain_create_info.sampleCount = config_view.recommendedSwapchainSampleCount;
    swapchain_create_info.usageFlags = XR_SWAPCHAIN_USAGE_SAMPLED_BIT | XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT;

    Swapchain swapchain;
    swapchain.width = config_view.recommendedImageRectWidth;
    swapchain.height = config_view.recommendedImageRectHeight;

    if (xrCreateSwapchain(session_, &swapchain_create_info, &swapchain.handle) != XR_SUCCESS) {
      ALOGE("xrCreateSwapchain failed for eye %d", i);
      return false;
    }

    uint32_t image_count = 0;
    xrEnumerateSwapchainImages(swapchain.handle, 0, &image_count, nullptr);
    swapchain.images.resize(image_count, {XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR});
    xrEnumerateSwapchainImages(swapchain.handle, image_count, &image_count,
                               reinterpret_cast<XrSwapchainImageBaseHeader*>(swapchain.images.data()));

    swapchains_.push_back(swapchain);
  }
  return true;
}

bool OpenXrContext::PollEvents() {
  XrEventDataBuffer event{XR_TYPE_EVENT_DATA_BUFFER};
  while (xrPollEvent(instance_, &event) == XR_SUCCESS) {
    switch (event.type) {
      case XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED: {
        auto* state_event = reinterpret_cast<XrEventDataSessionStateChanged*>(&event);
        session_state_ = state_event->state;
        if (state_event->state == XR_SESSION_STATE_READY) {
          XrSessionBeginInfo begin_info{XR_TYPE_SESSION_BEGIN_INFO};
          begin_info.primaryViewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
          xrBeginSession(session_, &begin_info);
          session_running_ = true;
        } else if (state_event->state == XR_SESSION_STATE_STOPPING) {
          xrEndSession(session_);
          session_running_ = false;
        }
        break;
      }
      case XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING:
        return false;
      default:
        break;
    }
  }
  return true;
}

bool OpenXrContext::BeginFrame(XrTime& out_display_time,
                               std::vector<XrCompositionLayerProjectionView>& out_views) {
  XrFrameWaitInfo wait_info{XR_TYPE_FRAME_WAIT_INFO};
  XrFrameState frame_state{XR_TYPE_FRAME_STATE};
  if (xrWaitFrame(session_, &wait_info, &frame_state) != XR_SUCCESS) return false;
  if (!frame_state.shouldRender) return false;

  out_display_time = frame_state.predictedDisplayTime;
  xrBeginFrame(session_, nullptr);

  XrViewLocateInfo view_locate_info{XR_TYPE_VIEW_LOCATE_INFO};
  view_locate_info.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
  view_locate_info.displayTime = out_display_time;
  view_locate_info.space = reference_space_;

  uint32_t view_count = 0;
  std::vector<XrView> views(swapchains_.size(), {XR_TYPE_VIEW});
  xrLocateViews(session_, &view_locate_info, nullptr, views.size(), &view_count, views.data());

  out_views.resize(view_count);
  for (uint32_t i = 0; i < view_count; ++i) {
    XrSwapchainImageAcquireInfo acquire_info{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
    int32_t image_index = 0;
    xrAcquireSwapchainImage(swapchains_[i].handle, &acquire_info, &image_index);

    out_views[i] = {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW};
    out_views[i].pose = views[i].pose;
    out_views[i].fov = views[i].fov;
    out_views[i].subImage.swapchain = swapchains_[i].handle;
    out_views[i].subImage.imageRect.offset = {0, 0};
    out_views[i].subImage.imageRect.extent = {swapchains_[i].width, swapchains_[i].height};
  }
  return true;
}

bool OpenXrContext::EndFrame(XrTime display_time,
                             const std::vector<XrCompositionLayerProjectionView>& views) {
  for (size_t i = 0; i < swapchains_.size(); ++i) {
    XrSwapchainImageReleaseInfo release_info{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
    xrReleaseSwapchainImage(swapchains_[i].handle, &release_info);
  }

  XrCompositionLayerProjection projection_layer{XR_TYPE_COMPOSITION_LAYER_PROJECTION};
  projection_layer.space = reference_space_;
  projection_layer.viewCount = static_cast<uint32_t>(views.size());
  projection_layer.views = views.data();

  const XrCompositionLayerBaseHeader* layers[] = {
      reinterpret_cast<const XrCompositionLayerBaseHeader*>(&projection_layer)};

  XrFrameEndInfo end_info{XR_TYPE_FRAME_END_INFO};
  end_info.displayTime = display_time;
  end_info.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
  end_info.layerCount = 1;
  end_info.layers = layers;

  return xrEndFrame(session_, &end_info) == XR_SUCCESS;
}

}  // namespace termisol
