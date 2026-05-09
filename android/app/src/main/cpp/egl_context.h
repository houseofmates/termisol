#ifndef TERMISOL_EGL_CONTEXT_H
#define TERMISOL_EGL_CONTEXT_H

#include <EGL/egl.h>
#include <android/native_window.h>

namespace termisol {

/** Minimal EGL context manager for OpenGL ES 3.x rendering. */
class EglContext {
 public:
  bool Initialize(ANativeWindow* window);
  void Shutdown();
  bool MakeCurrent();
  void SwapBuffers();
  bool IsValid() const;

  EGLDisplay display() const { return display_; }
  EGLConfig config() const { return config_; }
  EGLContext context() const { return context_; }

 private:
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLSurface surface_ = EGL_NO_SURFACE;
  EGLContext context_ = EGL_NO_CONTEXT;
  EGLConfig config_ = nullptr;
};

}  // namespace termisol

#endif  // TERMISOL_EGL_CONTEXT_H
