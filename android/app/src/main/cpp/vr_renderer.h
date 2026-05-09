#ifndef TERMISOL_VR_RENDERER_H
#define TERMISOL_VR_RENDERER_H

#include <GLES3/gl3.h>
#include <cstdint>
#include <vector>

namespace termisol {

/** Renders a terminal texture to an OpenGL framebuffer (swapchain image). */
class VrRenderer {
 public:
  bool Initialize();
  void Shutdown();

  void RenderEye(int eye_index, GLuint swapchain_image, int width, int height);
  void UpdateTerminalTexture(const uint8_t* pixels, int width, int height);

  GLuint terminal_texture() const { return terminal_texture_; }

 private:
  bool CompileShaders();

  GLuint terminal_texture_ = 0;
  GLuint shader_program_ = 0;
  GLuint vao_ = 0;
  GLuint vbo_ = 0;
  GLuint fbo_ = 0;
  int terminal_width_ = 0;
  int terminal_height_ = 0;
};

}  // namespace termisol

#endif  // TERMISOL_VR_RENDERER_H
