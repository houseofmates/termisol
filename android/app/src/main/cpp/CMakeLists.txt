cmake_minimum_required(VERSION 3.22.1)
project(termisol_vr)

set(CMAKE_CXX_STANDARD 17)

find_package(OpenXR REQUIRED)

add_library(termisol_vr SHARED
    jni_bridge.cpp
    openxr_context.cpp
    egl_context.cpp
    vr_renderer.cpp
)

target_link_libraries(termisol_vr
    OpenXR::openxr_loader
    EGL
    GLESv3
    android
    log
)
