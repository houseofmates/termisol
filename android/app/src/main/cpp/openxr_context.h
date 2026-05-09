#ifndef TERMISOL_OPENXR_CONTEXT_H
#define TERMISOL_OPENXR_CONTEXT_H

#include <EGL/egl.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include <vector>

namespace termisol {

struct Swapchain {
  XrSwapchain handle = XR_NULL_HANDLE;
  int32_t width = 0;
  int32_t height = 0;
  std::vector<XrSwapchainImageOpenGLESKHR> images;
};

/** Encapsulates OpenXR instance, session, reference space and swapchains. */
class OpenXrContext {
 public:
  bool Initialize(EGLDisplay display, EGLConfig config, EGLContext context);
  void Shutdown();

  bool IsSessionRunning() const { return session_running_; }
  bool PollEvents();

  bool BeginFrame(XrTime& out_display_time,
                  std::vector<XrCompositionLayerProjectionView>& out_views);
  bool EndFrame(XrTime display_time,
                const std::vector<XrCompositionLayerProjectionView>& views);

 private:
  bool CreateInstance();
  bool CreateSession(EGLDisplay display, EGLConfig config, EGLContext context);
  bool CreateReferenceSpace();
  bool CreateSwapchains();

  XrInstance instance_ = XR_NULL_HANDLE;
  XrSystemId system_id_ = XR_NULL_SYSTEM_ID;
  XrSession session_ = XR_NULL_HANDLE;
  XrSpace reference_space_ = XR_NULL_HANDLE;
  XrSessionState session_state_ = XR_SESSION_STATE_UNKNOWN;
  bool session_running_ = false;

  std::vector<XrViewConfigurationView> view_config_views_;
  std::vector<Swapchain> swapchains_;
};

}  // namespace termisol

#endif  // TERMISOL_OPENXR_CONTEXT_H
