#include "vr_renderer.h"
#include <android/log.h>

#define LOG_TAG "TermisolVR"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace termisol {

namespace {

const char* kVertexShader = R"(
    #version 300 es
    in vec2 aPosition;
    in vec2 aTexCoord;
    out vec2 vTexCoord;
    void main() {
        gl_Position = vec4(aPosition, 0.0, 1.0);
        vTexCoord = aTexCoord;
    }
)";

const char* kFragmentShader = R"(
    #version 300 es
    precision mediump float;
    in vec2 vTexCoord;
    out vec4 fragColor;
    uniform sampler2D uTexture;
    void main() {
        fragColor = texture(uTexture, vTexCoord);
    }
)";

GLuint CompileShader(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);
  GLint compiled = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (!compiled) {
    char log[512];
    glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
    ALOGE("Shader compile error: %s", log);
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

}  // namespace

bool VrRenderer::Initialize() {
  if (!CompileShaders()) return false;

  float vertices[] = {
      // positions    // texcoords
      -1.0f,  1.0f,  0.0f, 0.0f,
      -1.0f, -1.0f,  0.0f, 1.0f,
       1.0f, -1.0f,  1.0f, 1.0f,
      -1.0f,  1.0f,  0.0f, 0.0f,
       1.0f, -1.0f,  1.0f, 1.0f,
       1.0f,  1.0f,  1.0f, 0.0f,
  };

  glGenVertexArrays(1, &vao_);
  glGenBuffers(1, &vbo_);
  glBindVertexArray(vao_);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

  GLint pos_loc = glGetAttribLocation(shader_program_, "aPosition");
  GLint tex_loc = glGetAttribLocation(shader_program_, "aTexCoord");
  glEnableVertexAttribArray(pos_loc);
  glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
  glEnableVertexAttribArray(tex_loc);
  glVertexAttribPointer(tex_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                        reinterpret_cast<void*>(2 * sizeof(float)));

  glGenTextures(1, &terminal_texture_);
  glBindTexture(GL_TEXTURE_2D, terminal_texture_);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  glGenFramebuffers(1, &fbo_);
  return true;
}

void VrRenderer::Shutdown() {
  if (terminal_texture_) glDeleteTextures(1, &terminal_texture_);
  if (vbo_) glDeleteBuffers(1, &vbo_);
  if (vao_) glDeleteVertexArrays(1, &vao_);
  if (fbo_) glDeleteFramebuffers(1, &fbo_);
  if (shader_program_) glDeleteProgram(shader_program_);
}

bool VrRenderer::CompileShaders() {
  GLuint vs = CompileShader(GL_VERTEX_SHADER, kVertexShader);
  GLuint fs = CompileShader(GL_FRAGMENT_SHADER, kFragmentShader);
  if (!vs || !fs) return false;

  shader_program_ = glCreateProgram();
  glAttachShader(shader_program_, vs);
  glAttachShader(shader_program_, fs);
  glLinkProgram(shader_program_);

  GLint linked = 0;
  glGetProgramiv(shader_program_, GL_LINK_STATUS, &linked);
  if (!linked) {
    char log[512];
    glGetProgramInfoLog(shader_program_, sizeof(log), nullptr, log);
    ALOGE("Program link error: %s", log);
    glDeleteProgram(shader_program_);
    shader_program_ = 0;
    return false;
  }

  glDeleteShader(vs);
  glDeleteShader(fs);
  return true;
}

void VrRenderer::RenderEye(int eye_index, GLuint swapchain_image, int width, int height) {
  glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, swapchain_image, 0);

  glViewport(0, 0, width, height);
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glUseProgram(shader_program_);
  glBindVertexArray(vao_);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, terminal_texture_);
  glUniform1i(glGetUniformLocation(shader_program_, "uTexture"), 0);
  glDrawArrays(GL_TRIANGLES, 0, 6);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void VrRenderer::UpdateTerminalTexture(const uint8_t* pixels, int width, int height) {
  if (width <= 0 || height <= 0) return;

  glBindTexture(GL_TEXTURE_2D, terminal_texture_);
  if (width != terminal_width_ || height != terminal_height_) {
    terminal_width_ = width;
    terminal_height_ = height;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
  } else {
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
  }
}

}  // namespace termisol
