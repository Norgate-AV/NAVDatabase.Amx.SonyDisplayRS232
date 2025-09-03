PROGRAM_NAME='LibSonyDisplayRS232'

(***********************************************************)
#include 'NAVFoundation.Core.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/


#IF_NOT_DEFINED __LIB_SONYDISPLAYRS232__
#DEFINE __LIB_SONYDISPLAYRS232__ 'LibSonyDisplayRS232'

#include 'NAVFoundation.Math.axi'


DEFINE_CONSTANT

constant integer MAX_VOLUME = 100
constant integer MIN_VOLUME = 0

constant char HEADER_COMMAND = $8C
constant char HEADER_ENQUIRY = $83

constant char FUNCTION_POWER            = $00
constant char FUNCTION_STANDBY_CONTROL  = $01
constant char FUNCTION_INPUT            = $02
constant char FUNCTION_VOLUME           = $05
constant char FUNCTION_AUDIO_MUTE       = $06
constant char FUNCTION_VIDEO_MUTE       = $0D

constant char COMMAND_GET_POWER_STATUS[]        = {$00, $00, $FF, $FF}
constant char COMMAND_GET_INPUT_STATUS[]        = {$00, $02, $FF, $FF}
constant char COMMAND_GET_AUDIO_MUTE_STATUS[]   = {$00, $06, $FF, $FF}
constant char COMMAND_GET_VIDEO_MUTE_STATUS[]   = {$00, $0D, $FF, $FF}

constant char COMMAND_STANDBY_CONTROL_ON[]      = {$00, $01, $02, $01}

constant char COMMAND_POWER_ON[]                = {$00, $00, $02, $01}
constant char COMMAND_POWER_OFF[]               = {$00, $00, $02, $00}

constant char COMMAND_INPUT_HDMI_1[]            = {$00, $02, $03, $04, $01}
constant char COMMAND_INPUT_HDMI_2[]            = {$00, $02, $03, $04, $02}
constant char COMMAND_INPUT_HDMI_3[]            = {$00, $02, $03, $04, $03}
constant char COMMAND_INPUT_HDMI_4[]            = {$00, $02, $03, $04, $04}

constant char COMMAND_AUDIO_MUTE_ON[]           = {$00, $06, $03, $01, $01}
constant char COMMAND_AUDIO_MUTE_OFF[]          = {$00, $06, $03, $01, $00}

constant char COMMAND_VIDEO_MUTE_ON[]           = {$00, $0D, $03, $01, $00}
constant char COMMAND_VIDEO_MUTE_OFF[]          = {$00, $0D, $03, $01, $01}


define_function char[NAV_MAX_BUFFER] BuildProtocol(char header, char function, char data[]) {
    stack_var char payload[NAV_MAX_BUFFER]

    payload = "header, $00, function"

    switch (header) {
        case HEADER_COMMAND: {
            payload = "payload, length_array(data) + 1, data"
        }
        case HEADER_ENQUIRY: {
            payload = "payload, $FF, $FF"
        }
    }

    return "payload, NAVCalculateSumOfBytesChecksum(1, payload)"
}


#END_IF // __LIB_SONYDISPLAYRS232__
