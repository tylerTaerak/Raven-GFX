# Raven GFX (WIP)

This is a project of mine that is my foray into graphics programming. This is a rendering library that utilizes Vulkan
for high-performance rendering.

Raven uses bindless shaders to enable GPU-driven rendering. It also utilizes multiple threads to manage GPU jobs and
the draw commands to perform them, all while maintaining synchronization between jobs that need to wait on other jobs.
