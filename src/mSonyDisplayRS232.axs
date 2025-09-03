MODULE_NAME='mSonyDisplayRS232' (
                                    dev vdvObject,
                                    dev dvPort
                                )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
#DEFINE USING_NAV_STRING_GATHER_CALLBACK
#DEFINE USING_NAV_LOGIC_ENGINE_EVENT_CALLBACK
#DEFINE USING_NAV_DEVICE_PRIORITY_QUEUE_SEND_NEXT_ITEM_EVENT_CALLBACK
#DEFINE USING_NAV_DEVICE_PRIORITY_QUEUE_FAILED_RESPONSE_EVENT_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.LogicEngine.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.StringUtils.axi'
#include 'NAVFoundation.TimelineUtils.axi'
#include 'NAVFoundation.ErrorLogUtils.axi'
#include 'NAVFoundation.Math.axi'
#include 'NAVFoundation.DevicePriorityQueue.axi'
#include 'LibSonyDisplayRS232.axi'

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

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_SOCKET_CHECK           = 1
constant long TL_SOCKET_CHECK_INTERVAL[] = { 3000 }

constant integer REQUIRED_POWER_ON      = 1
constant integer REQUIRED_POWER_OFF     = 2

constant integer ACTUAL_POWER_ON        = 1
constant integer ACTUAL_POWER_OFF       = 2

constant integer INPUT_HDMI_1           = 1
constant integer INPUT_HDMI_2           = 2
constant integer INPUT_HDMI_3           = 3
constant integer INPUT_HDMI_4           = 4

constant char INPUT_SNAPI_PARAMS[][NAV_MAX_CHARS]   =   {
                                                            'HDMI,1',
                                                            'HDMI,2',
                                                            'HDMI,3',
                                                            'HDMI,4'
                                                        }

constant char INPUT_COMMANDS[][2]   =   {
                                            {$04, $01},
                                            {$04, $02},
                                            {$04, $03},
                                            {$04, $04}
                                        }

constant integer AUDIO_MUTE_ON        = 1
constant integer AUDIO_MUTE_OFF       = 2

constant integer GET_POWER          = 1
constant integer GET_INPUT          = 2
constant integer GET_AUDIO_MUTE     = 3
constant integer GET_VOLUME         = 4

constant integer MODE_SERIAL       = 1
constant integer MODE_IP_DIRECT    = 2
constant integer MODE_IP_INDIRECT  = 3


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _NAVDisplay object

volatile integer mode = MODE_SERIAL

volatile integer pollSequence = GET_POWER

volatile char inputInitialized = false
volatile char audioMuteInitialized = false
volatile char videoMuteInitialized = false

volatile char volumeBusy = false


(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)

define_function SendString(char payload[]) {
    send_string dvPort, "payload"
}


define_function EnqueueCommandItem(char item[]) {
    NAVDevicePriorityQueueEnqueue(priorityQueue, item, true)
}


define_function EnqueueQueryItem(char item[]) {
    NAVDevicePriorityQueueEnqueue(priorityQueue, item, false)
}


#IF_DEFINED USING_NAV_DEVICE_PRIORITY_QUEUE_SEND_NEXT_ITEM_EVENT_CALLBACK
define_function NAVDevicePriorityQueueSendNextItemEventCallback(char item[]) {
    SendString(item)
}
#END_IF


#IF_DEFINED USING_NAV_DEVICE_PRIORITY_QUEUE_FAILED_RESPONSE_EVENT_CALLBACK
define_function NAVDevicePriorityQueueFailedResponseEventCallback(_NAVDevicePriorityQueue queue) {
    module.Device.IsCommunicating = false
    UpdateFeedback()
}
#END_IF


define_function SendQuery(integer query) {
    switch (query) {
        case GET_POWER:         { EnqueueQueryItem(BuildProtocol(HEADER_ENQUIRY, FUNCTION_POWER, '')) }
        case GET_INPUT:         { EnqueueQueryItem(BuildProtocol(HEADER_ENQUIRY, FUNCTION_INPUT, '')) }
        case GET_AUDIO_MUTE:    { EnqueueQueryItem(BuildProtocol(HEADER_ENQUIRY, FUNCTION_AUDIO_MUTE, '')) }
        default:                { SendQuery(GET_POWER) }
    }
}


define_function CommunicationTimeOut(integer timeout) {
    cancel_wait 'TimeOut'

    module.Device.IsCommunicating = true
    UpdateFeedback()

    wait (timeout * 10) 'TimeOut' {
        module.Device.IsCommunicating = false
        UpdateFeedback()
    }
}


define_function Reset() {
    module.Device.SocketConnection.IsConnected = false
    module.Device.IsCommunicating = false
    module.Device.IsInitialized = false
    UpdateFeedback()

    NAVLogicEngineStop()
}


define_function SetPower(integer state) {
    switch (state) {
        case REQUIRED_POWER_ON:  { EnqueueCommandItem(BuildProtocol(HEADER_COMMAND, FUNCTION_POWER, "$01")) }
        case REQUIRED_POWER_OFF: { EnqueueCommandItem(BuildProtocol(HEADER_COMMAND, FUNCTION_POWER, "$00")) }
    }
}


define_function SetInput(integer input) {
    EnqueueCommandItem(BuildProtocol(HEADER_COMMAND, FUNCTION_INPUT, "INPUT_COMMANDS[input]"))
}


define_function SetVolume(sinteger level) {
    SendString(BuildProtocol(HEADER_COMMAND, FUNCTION_VOLUME, "$01, level"))
}


define_function SetAudioMute(integer state) {
    switch (state) {
        case AUDIO_MUTE_ON:     { SendString(BuildProtocol(HEADER_COMMAND, FUNCTION_AUDIO_MUTE, "$01, $01")) }
        case AUDIO_MUTE_OFF:    { SendString(BuildProtocol(HEADER_COMMAND, FUNCTION_AUDIO_MUTE, "$01, $00")) }
    }
}


define_function integer ModeIsIp(integer mode) {
    return mode == MODE_IP_DIRECT || mode == MODE_IP_INDIRECT
}


define_function MaintainSocketConnection() {
    if (module.Device.SocketConnection.IsConnected) {
        return
    }

    NAVClientSocketOpen(dvPort.PORT,
                        module.Device.SocketConnection.Address,
                        module.Device.SocketConnection.Port,
                        IP_TCP)
}


#IF_DEFINED USING_NAV_LOGIC_ENGINE_EVENT_CALLBACK
define_function NAVLogicEngineEventCallback(_NAVLogicEngineEvent args) {
    if (!module.Device.SocketConnection.IsConnected && ModeIsIp(mode)) {
        return;
    }

    if (priorityQueue.Busy) {
        return;
    }

    if (volumeBusy) {
        return
    }

    switch (args.Name) {
        case NAV_LOGIC_ENGINE_EVENT_QUERY: {
            SendQuery(pollSequence)
            return
        }
        case NAV_LOGIC_ENGINE_EVENT_ACTION: {
            if (module.CommandBusy) {
                return
            }

            if (object.PowerState.Required && (object.PowerState.Required == object.PowerState.Actual)) { object.PowerState.Required = 0; return }
            if (object.Input.Required && (object.Input.Required == object.Input.Actual)) { object.Input.Required = 0; return }
            if (object.Volume.Mute.Required && (object.Volume.Mute.Required == object.Volume.Mute.Actual)) { object.Volume.Mute.Required = 0; return }

            if (object.PowerState.Required && (object.PowerState.Required != object.PowerState.Actual)) {
                SetPower(object.PowerState.Required)
                module.CommandBusy = true
                wait 80 module.CommandBusy = false
                pollSequence = GET_POWER
                return
            }

            if (object.Input.Required && (object.PowerState.Actual == ACTUAL_POWER_ON) && (object.Input.Required != object.Input.Actual)) {
                SetInput(object.Input.Required)
                module.CommandBusy = true
                wait 20 module.CommandBusy = false
                pollSequence = GET_INPUT
                return
            }

            if (object.Volume.Mute.Required && (object.PowerState.Actual == ACTUAL_POWER_ON) && (object.Volume.Mute.Required != object.Volume.Mute.Actual)) {
                SetAudioMute(object.Volume.Mute.Required)
                module.CommandBusy = true
                wait 20 module.CommandBusy = false
                pollSequence = GET_AUDIO_MUTE
                return
            }
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_STRING_GATHER_CALLBACK
define_function NAVStringGatherCallback(_NAVStringGatherResult args) {
    stack_var char data[NAV_MAX_BUFFER]
    stack_var char delimiter[NAV_MAX_CHARS]

    data = args.Data
    delimiter = args.Delimiter

    if (ModeIsIp(mode)) {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                    NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM,
                                                dvPort,
                                                data))
    }

    select {
        active (NAVStartsWith(priorityQueue.LastMessage, "HEADER_COMMAND")): {
            module.RxBuffer.Data = NAVStripLeft(module.RxBuffer.Data, 2)
        }
        active (NAVStartsWith(priorityQueue.LastMessage, "HEADER_ENQUIRY")): {
            stack_var char code

            code = module.RxBuffer.Data[1]
            module.RxBuffer.Data = NAVStripLeft(module.RxBuffer.Data, 1)

            switch (code) {
                case $00: {
                    stack_var integer length

                    length = module.RxBuffer.Data[1]
                    module.RxBuffer.Data = NAVStripLeft(module.RxBuffer.Data, 1)

                    data = NAVStripRight(NAVRemoveStringByLength(module.RxBuffer.Data, length), 1)

                    select {
                        active (NAVContains(priorityQueue.LastMessage, COMMAND_GET_POWER_STATUS)): {
                            switch (data[1]) {
                                case $00: {
                                    object.PowerState.Actual = ACTUAL_POWER_OFF
                                    object.VideoMute.Actual = AUDIO_MUTE_OFF
                                }
                                case $01: {
                                    if (object.PowerState.Actual == ACTUAL_POWER_ON) {
                                        break
                                    }

                                    object.PowerState.Actual = ACTUAL_POWER_ON
                                    EnqueueCommandItem(BuildProtocol(HEADER_COMMAND, FUNCTION_STANDBY_CONTROL, "$01"))

                                    select {
                                        active (!inputInitialized): {
                                            pollSequence = GET_INPUT
                                        }
                                        active (!audioMuteInitialized): {
                                            pollSequence = GET_AUDIO_MUTE
                                        }
                                        // case (!videoMuteInitialized): {
                                        //     pollSequence = GET_VIDEO_MUTE
                                        // }
                                    }
                                }
                            }
                        }
                        active (NAVContains(priorityQueue.LastMessage, COMMAND_GET_INPUT_STATUS)): {
                            select {
                                active (data == "$04, $01"): {
                                    object.Input.Actual = INPUT_HDMI_1
                                }
                                active (data == "$04, $02"): {
                                    object.Input.Actual = INPUT_HDMI_2
                                }
                                active (data == "$04, $03"): {
                                    object.Input.Actual = INPUT_HDMI_3
                                }
                                active (data == "$04, $04"): {
                                    object.Input.Actual = INPUT_HDMI_4
                                }
                            }

                            inputInitialized = true
                            pollSequence = GET_POWER
                        }
                        active (NAVContains(priorityQueue.LastMessage, COMMAND_GET_AUDIO_MUTE_STATUS)): {
                            select {
                                active (data == "$01, $01"): {
                                    object.Volume.Mute.Actual = AUDIO_MUTE_ON
                                }
                                active (data == "$01, $00"): {
                                    object.Volume.Mute.Actual = AUDIO_MUTE_OFF
                                }
                            }

                            audioMuteInitialized = true
                            pollSequence = GET_POWER
                        }
                        // active (NAVContains(priorityQueue.LastMessage, COMMAND_GET_VIDEO_MUTE_STATUS)): {
                        //     select {
                        //         active (data == "$01, $01"): {
                        //             object.VideoMute.Actual = AUDIO_MUTE_ON
                        //         }
                        //         active (data == "$01, $00"): {
                        //             object.VideoMute.Actual = AUDIO_MUTE_OFF
                        //         }
                        //     }

                        //     videoMuteInitialized = true
                        //     pollSequence = GET_POWER
                        // }
                    }
                }
                case $03: {
                    module.RxBuffer.Data = NAVStripLeft(module.RxBuffer.Data, 2)
                    pollSequence = GET_POWER
                }
            }
        }
    }

    NAVDevicePriorityQueueGoodResponse(priorityQueue)
}
#END_IF


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    switch (event.Name) {
        case NAV_MODULE_PROPERTY_EVENT_IP_ADDRESS: {
            module.Device.SocketConnection.Address = NAVTrimString(event.Args[1])
            NAVTimelineStart(TL_SOCKET_CHECK,
                                TL_SOCKET_CHECK_INTERVAL,
                                TIMELINE_ABSOLUTE,
                                TIMELINE_REPEAT)
        }
        case NAV_MODULE_PROPERTY_EVENT_PORT: {
            module.Device.SocketConnection.Port = atoi(event.Args[1])
        }
        case 'COMM_MODE': {
            switch (event.Args[1]) {
                case 'SERIAL': {
                    mode = MODE_SERIAL
                }
                case 'IP_DIRECT': {
                    mode = MODE_IP_DIRECT
                }
                case 'IP_INDIRECT': {
                    mode = MODE_IP_INDIRECT
                }
            }
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
define_function NAVModulePassthruEventCallback(_NAVModulePassthruEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    SendString(event.Payload)
}
#END_IF


define_function HandleSnapiMessage(_NAVSnapiMessage message, tdata data) {
    switch (message.Header) {
        case 'POWER': {
            switch (message.Parameter[1]) {
                case 'ON': {
                    object.PowerState.Required = REQUIRED_POWER_ON
                }
                case 'OFF': {
                    object.PowerState.Required = REQUIRED_POWER_OFF
                    object.Input.Required = 0
                }
            }
        }
        case 'MUTE': {
            if (object.PowerState.Actual != ACTUAL_POWER_ON) {
                return
            }

            switch (message.Parameter[1]) {
                case 'ON': {
                    object.Volume.Mute.Required = AUDIO_MUTE_ON
                }
                case 'OFF': {
                    object.Volume.Mute.Required = AUDIO_MUTE_OFF
                }
            }
        }
        case 'VOLUME': {
            switch (message.Parameter[1]) {
                case 'ABS': {
                    volumeBusy = true
                    VolumeCommandBusyTimeOut()

                    SetVolume(atoi(message.Parameter[2]))
                    // pollSequence = GET_VOLUME
                    NAVDevicePriorityQueueInit(priorityQueue)
                }
                default: {
                    volumeBusy = true
                    VolumeCommandBusyTimeOut()

                    SetVolume(atoi(message.Parameter[1]) * 100 / 255)
                    // pollSequence = GET_VOLUME
                    NAVDevicePriorityQueueInit(priorityQueue)
                }
            }
        }
        case 'INPUT': {
            stack_var integer input
            stack_var char inputCommand[NAV_MAX_CHARS]

            NAVTrimStringArray(message.Parameter)
            inputCommand = NAVArrayJoinString(message.Parameter, ',')

            input = NAVFindInArrayString(INPUT_SNAPI_PARAMS, inputCommand)

            if (input <= 0) {
                NAVErrorLog(NAV_LOG_LEVEL_WARNING,
                            "'mSonyDisplayRS232 => Invalid input: ', inputCommand")

                return
            }



            object.PowerState.Required = REQUIRED_POWER_ON
            object.Input.Required = input
        }
    }
}


define_function UpdateFeedback() {
    [vdvObject, POWER_FB]    = (object.PowerState.Actual == ACTUAL_POWER_ON)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
    [vdvObject, DATA_INITIALIZED] = (module.Device.IsInitialized)
    [vdvObject, VOL_MUTE_FB]    = (object.Volume.Mute.Actual == AUDIO_MUTE_ON)
}


define_function VolumeCommandBusyTimeOut() {
    cancel_wait 'VolumeCommandBusyWait'

    wait 20 'VolumeCommandBusyWait' {
        volumeBusy = false
    }
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort, module.RxBuffer.Data
    module.Device.SocketConnection.Socket = dvPort.PORT
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        if (data.device.number != 0) {
            NAVCommand(data.device, "'SET BAUD 9600,N,8,1 485 DISABLE'")
            NAVCommand(data.device, "'B9MOFF'")
            NAVCommand(data.device, "'CHARD-0'")
            NAVCommand(data.device, "'CHARDM-0'")
            NAVCommand(data.device, "'HSOFF'")
        }

        if (data.device.number == 0) {
            module.Device.SocketConnection.IsConnected = true
            UpdateFeedback()
        }

        NAVLogicEngineStart()
    }
    string: {
        CommunicationTimeOut(30)

        if (data.device.number == 0) {
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                        NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM,
                                                    data.device,
                                                    data.text))
        }

        select {
            active(true): {
                NAVStringGather(module.RxBuffer, 'p')
            }
        }
    }
    offline: {
        if (data.device.number == 0) {
            NAVClientSocketClose(data.device.port)
            Reset()
        }
    }
    onerror: {
        if (data.device.number == 0) {
            Reset()
        }

        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "'mSonyDisplayRS232 => OnError: ', NAVGetSocketError(type_cast(data.number))")
    }
}


data_event[vdvObject] {
    online: {
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_DESCRIPTION,Monitor'")
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_MANUFACTURER_URL,www.lg.com'")
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_MANUFACTURER_NAME,LG'")
    }
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        HandleSnapiMessage(message, data)
    }
}


channel_event[vdvObject, 0] {
    on: {
        switch (channel.channel) {
            case PWR_ON: {
                object.PowerState.Required = REQUIRED_POWER_ON
            }
            case PWR_OFF: {
                object.PowerState.Required = REQUIRED_POWER_OFF
                object.Input.Required = 0
            }
        }
    }
}


timeline_event[TL_SOCKET_CHECK] {
    MaintainSocketConnection()
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
