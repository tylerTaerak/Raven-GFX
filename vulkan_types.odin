#+build windows, linux, freebsd, openbsd, netbsd
package gfx

import vulk "./vulkan"

API_Instance 			:: vulk.Instance
API_Device 	 			:: vulk.Device
API_Swapchain 			:: vulk.Swapchain
API_Image 	  			::vulk.Render_Image
API_Timeline_Semaphore 	:: vulk.Timeline
API_Binary_Semaphore   	:: vulk.Semaphore
API_Fence 			   	:: vulk.Fence
API_Command_Collection 	:: vulk.Command_Set
API_Command_Buffer 	   	:: vulk.Command_Buffer
API_Descriptor_Set 	   	:: vulk.Descriptor_Set
API_Shader_Set 		   	:: vulk.Shader_Chain
API_Shader 			   	:: vulk.Shader
