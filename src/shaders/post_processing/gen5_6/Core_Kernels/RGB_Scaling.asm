/*
 * All Video Processing kernels 
 * Copyright © <2010>, Intel Corporation.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sub license, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT.
 * IN NO EVENT SHALL PRECISION INSIGHT AND/OR ITS SUPPLIERS BE LIABLE FOR
 * ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * This file was originally licensed under the following license
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

//---------- RGB_Scaling.asm ----------
#include "Scaling.inc"

	// Build 16 elements ramp in float32 and normalized it
//	mov (8)		SAMPLER_RAMP(0)<1>		0x76543210:v
//	add	(8)		SAMPLER_RAMP(1)<1>		SAMPLER_RAMP(0)	8.0:f
mov (4) SAMPLER_RAMP(0)<1> 0x48403000:vf		//3, 2, 1, 0 in float vector
mov (4) SAMPLER_RAMP(0,4)<1> 0x5C585450:vf	//7, 6, 5, 4 in float vector
add	(8)		SAMPLER_RAMP(1)<1>		SAMPLER_RAMP(0)	8.0:f

//Module: PrepareScaleCoord.asm

	// Setup for sampler msg hdr
    mov (2)		rMSGSRC.0<1>:ud			0:ud						{ NoDDClr }	// Unused fields
    mov (1)		rMSGSRC.2<1>:ud			0:ud						{ NoDDChk }	// Write and offset

	// Calculate 16 v based on the step Y and vertical origin
	mov	(16)	mfMSGPAYLOAD(2)<1>		fSRC_VID_V_ORI<0;1,0>:f
	mov	(16)	SCALE_COORD_Y<1>:f		fSRC_VID_V_ORI<0;1,0>:f

	// Calculate 16 u based on the step X and hori origin
//	line (16)	mfMSGPAYLOAD(0)<1>		SCALE_STEP_X<0;1,0>:f		SAMPLER_RAMP(0) 	// Assign to mrf directly
	mov	(16)	acc0:f							fSRC_VID_H_ORI<0;1,0>:f											{ Compr }
	mac	(16)	mfMSGPAYLOAD(0)<1>	fVIDEO_STEP_X<0;1,0>:f	SAMPLER_RAMP(0)			{ Compr }			

	//Setup the constants for line instruction
	mov 	(1)		SCALE_LINE_P255<1>:f		255.0:f 			{ NoDDClr }	//{ NoDDClr, NoDDChk }
	mov 	(1)		SCALE_LINE_P0_5<1>:f		0.5:f 				{ NoDDChk }

	
//------------------------------------------------------------------------------

$for (0; <nY_NUM_OF_ROWS; 1) {

	// Read 16 sampled pixels and store them in float32 in 8 GRFs in the order of BGRA (VYUA).
  mov (8) 	MSGHDR_SCALE.0:ud      rMSGSRC.0<8;8,1>:ud    // Copy msg header and payload mirrors to MRFs
	send (16)	SCALE_RESPONSE_YW(0)<1>		MSGHDR_SCALE	udDUMMY_NULL	nSMPL_ENGINE SMPLR_MSG_DSC+nSI_SRC_SIMD16_RGB+nBI_CURRENT_SRC_RGB

	// Calculate 16 v for next line
	add (16)	mfMSGPAYLOAD(2)<1>		SCALE_COORD_Y<8;8,1>:f		fVIDEO_STEP_Y<0;1,0>:f	// Assign to mrf directly
	add (16)	SCALE_COORD_Y<1>:f		SCALE_COORD_Y<8;8,1>:f		fVIDEO_STEP_Y<0;1,0>:f	// Assign to mrf directly

	// Scale back to [0, 255], convert f to ud
	line (16)	acc0:f		SCALE_LINE_P255<0;1,0>:f	SCALE_RESPONSE_YF(0)	{ Compr }			// Process B, V
	mov  (16) SCALE_RESPONSE_YD(0)<1>	acc0:f														{ Compr }

	line (16)	acc0:f		SCALE_LINE_P255<0;1,0>:f	SCALE_RESPONSE_YF(2)	{ Compr }			// Process B, V
	mov  (16) SCALE_RESPONSE_YD(2)<1>	acc0:f														{ Compr }

	line (16)	acc0:f		SCALE_LINE_P255<0;1,0>:f	SCALE_RESPONSE_YF(4)	{ Compr }			// Process B, V
	mov  (16) SCALE_RESPONSE_YD(4)<1>	acc0:f														{ Compr }

//#if defined(SAVE_ARGB)	//Only needed if Alpha value is written to the destination
	line (16)	acc0:f		SCALE_LINE_P255<0;1,0>:f	SCALE_RESPONSE_YF(6)	{ Compr }			// Process B, V
	mov  (16) SCALE_RESPONSE_YD(6)<1>	acc0:f														{ Compr }
//#endif

	mov	 (16) 	DEST_R(%1)<1>				SCALE_RESPONSE_YB(0)											//possible error due to truncation - vK
	mov	 (16) 	DEST_G(%1)<1>				SCALE_RESPONSE_YB(2)											//possible error due to truncation - vK
	mov	 (16) 	DEST_B(%1)<1>				SCALE_RESPONSE_YB(4)											//possible error due to truncation - vK
	mov	 (16) 	DEST_A(%1)<1>				SCALE_RESPONSE_YB(6)											//possible error due to truncation - vK
}
