#+build windows, linux, freebsd, openbsd, netbsd
package gfx

import vulk "./vulkan"

Backend_Context             :: vulk.Context
Swapchain                   :: vulk.Swapchain
Pipeline                    :: vulk.Pipeline
Pipeline_Config             :: vulk.Pipeline_Config
Descriptor_Set              :: vulk.Descriptor_Collection
Descriptor_Config           :: vulk.Descriptor_Config
Buffer                      :: vulk.Buffer
Host_Buffer                 :: vulk.Host_Buffer
Buffer_Slice                :: vulk.Buffer_Slice
Image                       :: vulk.Render_Image
QueueTypes                  :: vulk.QueueTypes
QueueFamily                 :: vulk.QueueFamily
Timeline                    :: vulk.Timeline
Fence                       :: vulk.Fence
CommandSet                  :: vulk.Command_Set
Semaphore                   :: vulk.Semaphore
