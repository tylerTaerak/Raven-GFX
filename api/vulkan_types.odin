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
Shader_Set 		   	:: vulk.Shader_Chain
Shader 			   	:: vulk.Shader
