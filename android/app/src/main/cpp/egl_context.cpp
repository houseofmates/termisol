#include "egl_context.h"
#include <android/log.h>

#define LOG_TAG "TermisolVR"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace termisol {

bool EglContext::Initialize(ANativeWindow* window) {
  display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (display_ == EGL_NO_DISPLAY) {
    ALOGE("eglGetDisplay failed");
    return false;
  }

  EGLint major = 0, minor = 0;
  if (!eglInitialize(display_, &major, &minor)) {
    ALOGE("eglInitialize failed");
    return false;
  }

  EGLint attribs[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 8,
      EGL_GREEN_SIZE, 8,
      EGL_BLUE_SIZE, 8,
      EGL_ALPHA_SIZE, 8,
      EGL_DEPTH_SIZE, 16,
      EGL_NONE};

  EGLint num_configs = 0;
  if (!eglChooseConfig(display_, attribs, &config_, 1, &num_configs) || num_configs < 1) {
    ALOGE("eglChooseConfig failed");
    return false;
  }

  EGLint context_attribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, context_attribs);
  if (context_ == EGL_NO_CONTEXT) {
    ALOGE("eglCreateContext failed");
    return false;
  }

  surface_ = eglCreateWindowSurface(display_, config_, window, nullptr);
  if (surface_ == EGL_NO_SURFACE) {
    ALOGE("eglCreateWindowSurface failed");
    return false;
  }

  if (!MakeCurrent()) {
    return false;
  }

  ALOGI("EGL initialized: %d.%d", major, minor);
  return true;
}

void EglContext::Shutdown() {
  if (display_ != EGL_NO_DISPLAY) {
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (surface_ != EGL_NO_SURFACE) eglDestroySurface(display_, surface_);
    if (context_ != EGL_NO_CONTEXT) eglDestroyContext(display_, context_);
    eglTerminate(display_);
  }
  display_ = EGL_NO_DISPLAY;
  surface_ = EGL_NO_SURFACE;
  context_ = EGL_NO_CONTEXT;
}

bool EglContext::MakeCurrent() {
  if (!eglMakeCurrent(display_, surface_, surface_, context_)) {
    ALOGE("eglMakeCurrent failed");
    return false;
  }
  return true;
}

void EglContext::SwapBuffers() {
  eglSwapBuffers(display_, surface_);
}

bool EglContext::IsValid() const {
  return display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE && context_ != EGL_NO_CONTEXT;
}

}  // namespace termisol
