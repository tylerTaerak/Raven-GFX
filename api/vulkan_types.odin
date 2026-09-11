#+build windows, linux, freebsd, openbsd, netbsd
package api

import vulk "./vulkan"

Instance 			:: vulk.Instance
Device 	 			:: vulk.Device
Swapchain 			:: vulk.Swapchain
Memory 				:: vulk.Memory
Buffer 				:: vulk.Buffer
Image 	  			:: vulk.Render_Image
Timeline_Semaphore 	:: vulk.Timeline
Binary_Semaphore   	:: vulk.Semaphore
Fence 			   	:: vulk.Fence
Command_Collection 	:: vulk.Command_Set
Command_Buffer 	   	:: vulk.Command_Buffer
Descriptor_Set 	   	:: vulk.Descriptor_Set
Slice 				:: vulk.Allocation

Allocation_Location :: vulk.Allocation_Location

Shader 				:: vulk.Shader
Shader_Schema 		:: vulk.Descriptor_Layout
Shader_Element 		:: vulk.Descriptor_Param
Shader_Data 		:: vulk.Descriptor_Set
Shader_Config 		:: vulk.Shader_Config
