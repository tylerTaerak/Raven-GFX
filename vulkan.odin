#+build linux, freebsd, openbsd, netbsd
#+private
package gfx

import vulk "./vulkan"

/**
  This file defines the types used in Raven for using a Vulkan backend
*/

Backend_Context :: vulk.Context

Swapchain :: vulk.Swapchain

Pipeline :: vulk.Pipeline

Descriptor_Set :: vulk.Descriptor_Collection

// need AcquireNextImage, PresentImage
