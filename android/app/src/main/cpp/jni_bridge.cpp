#include <android/bitmap.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include "egl_context.h"
#include "openxr_context.h"
#include "vr_renderer.h"

#define LOG_TAG "TermisolVR"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace termisol {

static std::unique_ptr<OpenXrContext> g_openxr;
static std::unique_ptr<EglContext> g_egl;
static std::unique_ptr<VrRenderer> g_renderer;
static std::atomic<bool> g_running{false};
static std::thread g_render_thread;
static ANativeWindow* g_window = nullptr;

static std::vector<uint8_t> g_terminal_pixels;
static int g_terminal_width = 0;
static int g_terminal_height = 0;
static std::mutex g_terminal_mutex;

extern "C" {

JNIEXPORT void JNICALL
Java_com_termisol_vr_VrActivity_nativeOnCreate(JNIEnv* env, jobject /*thiz*/, jobject surface) {
  g_window = ANativeWindow_fromSurface(env, surface);
}

JNIEXPORT void JNICALL
Java_com_termisol_vr_VrActivity_nativeOnDestroy(JNIEnv* /*env*/, jobject /*thiz*/) {
  g_running = false;
  if (g_render_thread.joinable()) {
    g_render_thread.join();
  }
  if (g_renderer) g_renderer->Shutdown();
  if (g_openxr) g_openxr->Shutdown();
  if (g_egl) g_egl->Shutdown();
  if (g_window) {
    ANativeWindow_release(g_window);
    g_window = nullptr;
  }
}

JNIEXPORT void JNICALL
Java_com_termisol_vr_VrActivity_nativeStartVR(JNIEnv* /*env*/, jobject /*thiz*/) {
  g_render_thread = std::thread([]() {
    g_egl = std::make_unique<EglContext>();
    if (!g_egl->Initialize(g_window)) {
      ALOGE("Failed to initialize EGL");
      return;
    }

    g_openxr = std::make_unique<OpenXrContext>();
    if (!g_openxr->Initialize(g_egl->display(), g_egl->config(), g_egl->context())) {
      ALOGE("Failed to initialize OpenXR");
      return;
    }

    g_renderer = std::make_unique<VrRenderer>();
    if (!g_renderer->Initialize()) {
      ALOGE("Failed to initialize VR renderer");
      return;
    }

    g_running = true;
    while (g_running && g_openxr->PollEvents()) {
      if (!g_openxr->IsSessionRunning()) {
        continue;
      }

      XrTime display_time;
      std::vector<FrameView> views;
      if (!g_openxr->BeginFrame(display_time, views)) continue;

      // Update terminal texture if new data is available.
      {
        std::lock_guard<std::mutex> lock(g_terminal_mutex);
        if (!g_terminal_pixels.empty() && g_terminal_width > 0 && g_terminal_height > 0) {
          g_renderer->UpdateTerminalTexture(g_terminal_pixels.data(), g_terminal_width,
                                            g_terminal_height);
        }
      }

      // Render each eye to its acquired swapchain image.
      for (size_t i = 0; i < views.size(); ++i) {
        g_renderer->RenderEye(static_cast<int>(i), views[i].framebufferTexture,
                              views[i].width, views[i].height);
      }

      g_openxr->EndFrame(display_time, views);
    }
  });
}

JNIEXPORT void JNICALL
Java_com_termisol_vr_VrActivity_nativeUpdateTerminalTexture(JNIEnv* env, jobject /*thiz*/,
                                                            jobject bitmap) {
  AndroidBitmapInfo info;
  void* pixels = nullptr;
  if (AndroidBitmap_getInfo(env, bitmap, &info) < 0) return;
  if (info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) return;
  if (AndroidBitmap_lockPixels(env, bitmap, &pixels) < 0) return;

  {
    std::lock_guard<std::mutex> lock(g_terminal_mutex);
    g_terminal_width = static_cast<int>(info.width);
    g_terminal_height = static_cast<int>(info.height);
    size_t size = info.width * info.height * 4;
    g_terminal_pixels.resize(size);
    memcpy(g_terminal_pixels.data(), pixels, size);
  }

  AndroidBitmap_unlockPixels(env, bitmap);
}

}  // extern "C"

}  // namespace termisol
