-- Lua API of the Motion plugin, which an app loads with `require('motion')`: the accelerometer, the gyroscope and the attitude of the device, and the tilt that the accelerometer measures. The native part of each platform runs the sensors and sends their readings batched, so the listener of this module runs once per frame with every reading of the frame and keeps the newest one of each sensor.
local async = require('async')
local haylen = require('haylen')
local native = require('haylen.native')
local permissions = require('permissions')
local platform = require('haylen.platform')
local scene = require('haylen.scene')

local handle = platform.plugin('motion')
local motion = {}

local kDesktops = {macos = true, windows = true, linux = true}
local kSensors = {accelerometer = true, gyroscope = true, attitude = true}
local kOptions = {sensors = true, rate = true, owner = true}
local kDefaultRate = 60
local kMinRate = 1
local kMaxRate = 200

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the C++ library of `native/`, which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('motion', {init = 'motion_haylen_init'})
end

local permission = permissions.declare('motion', {'motion'})

-- Returns a platform call whose `await` gives the state of the permission `motion`, without asking the person, or `nil` and an error with the code `unsupported`, the reason and `data.missing` for a requirement that the project lacks.
motion.permission = permission.state

-- Returns a platform call whose `await` gives the state of the permission `motion` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported`, the reason and `data.missing` for a requirement that the project lacks.
motion.requestPermission = permission.request

-- The newest readings in the axes of the screen, the sensors that delivered them in this session, the level of the tilt, and the session that runs, whose `watch` call the native part holds while the sensors run.
local readings = {acceleration = {0, 0, 0}, rotationRate = {0, 0, 0}, attitude = {0, 0, 0, 1}}
local delivered = {}
local level = {0, 0, 1}
local session = nil
local sessions = 0

-- Turns a vector along the axes of the device in its natural orientation into the axes of the screen, for a device turned counterclockwise by the quarter turns while the screen keeps the app upright.
local function turnVector(x, y, z, turns)
    if turns == 1 then
        return -y, x, z
    end
    if turns == 2 then
        return -x, -y, z
    end
    if turns == 3 then
        return y, -x, z
    end
    return x, y, z
end

-- The screen turned clockwise against the device, so its axes reach the world through that turn first.
local function turnAttitude(x, y, z, w, turns)
    local half = -turns * math.pi / 4
    local bz, bw = math.sin(half), math.cos(half)
    return x * bw + y * bz, y * bw - x * bz, w * bz + z * bw, w * bw - z * bz
end

local function store(reading)
    local turns = reading.turns % 4
    if reading.sensor == 'attitude' then
        local x, y, z, w = turnAttitude(reading.x, reading.y, reading.z, reading.w, turns)
        readings.attitude = {x, y, z, w}
    else
        local x, y, z = turnVector(reading.x, reading.y, reading.z, turns)
        readings[reading.sensor == 'accelerometer' and 'acceleration' or 'rotationRate'] = {x, y, z}
    end
    delivered[reading.sensor] = true
end

-- Readings of a session that already ended may still arrive in the frame after it, so only those of the session that runs count.
handle:on('reading', function(batch)
    for _, reading in ipairs(batch) do
        if session and reading.session == session.id then
            store(reading)
        end
    end
end)

local function clearReadings()
    readings = {acceleration = {0, 0, 0}, rotationRate = {0, 0, 0}, attitude = {0, 0, 0, 1}}
    delivered = {}
end

local function endSession()
    if not session then
        return
    end
    session.watch:cancel()
    session = nil
    clearReadings()
end

local function readSensors(list)
    if list == nil then
        return {'accelerometer'}
    end
    if type(list) ~= 'table' then
        error("The option \"sensors\" of the motion sensors must be a list of sensor names, such as {'accelerometer', 'gyroscope'}.", 3)
    end
    if #list == 0 then
        error('The motion sensors need at least one sensor, such as "accelerometer".', 3)
    end

    local names = {}
    for index, name in ipairs(list) do
        if not kSensors[name] then
            error(string.format('The motion sensor "%s" does not exist. Use "accelerometer", "gyroscope" or "attitude".', tostring(name)), 3)
        end
        names[index] = name
    end
    return names
end

local function readRate(value)
    if value == nil then
        return kDefaultRate
    end
    if type(value) ~= 'number' or not (value >= kMinRate and value <= kMaxRate) then
        error('The rate of the motion sensors must be from 1 to 200 readings per second.', 3)
    end
    return value
end

-- Holds the session while its watch lasts, and for as long as its owner lives. The task stops for good when the owner ends, which closes its variable and ends the session, and a watch that the native part ends, such as on a platform without sensors, ends the session too.
local function keep(current, owner)
    local function hold()
        local closer <close> = setmetatable({}, {__close = function()
            if session == current then
                endSession()
            end
        end})
        current.watch:await()
    end

    if owner ~= nil then
        scene.spawn(owner, hold)
        return
    end
    async.spawn(hold)
end

-- Starts the sensors of `options.sensors`, `{'accelerometer'}` by default, at `options.rate` readings per second, 60 by default, and stops what an earlier start ran. Returns a platform call, whose `await` gives `{sensors}` once they run, or `nil` and the error, with the code `unsupported` for a device or a platform without the sensors, `denied` for a person who refused the permission `motion`, which `motion.requestPermission()` asks for, `failed` for a browser that asks only during a tap and `cancelled` for a start that `stop` or the end of its owner gave up. The sensors stop in the background, and with `options.owner` when it ends.
function motion.start(options)
    options = options or {}
    if type(options) ~= 'table' then
        error('The options of the motion sensors must be a table.', 2)
    end

    for key in pairs(options) do
        if not kOptions[key] then
            error(string.format('Unknown option "%s".', tostring(key)), 2)
        end
    end

    local sensors = readSensors(options.sensors)
    local rate = readRate(options.rate)

    endSession()
    sessions = sessions + 1
    local current = {id = sessions}
    current.watch = handle:call('watch', {session = current.id})
    session = current

    keep(current, options.owner)
    return handle:call('start', {session = current.id, sensors = sensors, rate = rate})
end

-- Stops the sensors that run, which also gives up a start that still waits for its answer.
function motion.stop()
    endSession()
end

-- Returns the list of the sensors that delivered readings since the sensors started, such as `{'accelerometer', 'gyroscope'}`.
function motion.sensors()
    local list = {}
    for _, name in ipairs({'accelerometer', 'gyroscope', 'attitude'}) do
        if delivered[name] then
            list[#list + 1] = name
        end
    end
    return list
end

-- Returns the `x`, `y` and `z` of the acceleration with gravity in meters per second squared, in the axes of the screen.
function motion.acceleration()
    local value = readings.acceleration
    return value[1], value[2], value[3]
end

-- Returns how fast the device turns around the `x`, `y` and `z` axes of the screen in radians per second.
function motion.rotationRate()
    local value = readings.rotationRate
    return value[1], value[2], value[3]
end

-- Returns the `x`, `y`, `z` and `w` of the unit quaternion that turns the axes of the screen into a frame whose z points up.
function motion.attitude()
    local value = readings.attitude
    return value[1], value[2], value[3], value[4]
end

-- Returns how far the device leans from level as the `x` and `y` of a vector up to 1 that follows design space like a stick, or `0, 0` without a reading of the accelerometer.
function motion.tilt()
    if not delivered.accelerometer then
        return 0, 0
    end
    local ax, ay, az = motion.acceleration()
    local length = math.sqrt(ax * ax + ay * ay + az * az)
    if length <= 0 then
        return 0, 0
    end
    local upX, upY, upZ = ax / length, ay / length, az / length

    -- The rotation that takes the level direction onto z turns around the axis of their cross product, by the angle between them, with the formula of Rodrigues.
    local axisX, axisY = level[2], -level[1]
    local sine = math.sqrt(axisX * axisX + axisY * axisY)
    local cosine = level[3]
    local turnedX, turnedY = upX, upY
    if sine > 1e-6 then
        local unitX, unitY = axisX / sine, axisY / sine
        local along = unitX * upX + unitY * upY
        turnedX = upX * cosine + unitY * upZ * sine + unitX * along * (1 - cosine)
        turnedY = upY * cosine - unitX * upZ * sine + unitY * along * (1 - cosine)
    elseif cosine < 0 then
        turnedY = -upY
    end

    -- Gravity leans toward the edge that goes up, so the ball rolls the other way, and design space grows down.
    local x, y = -turnedX, turnedY
    local size = math.sqrt(x * x + y * y)
    if size > 1 then
        return x / size, y / size
    end
    return x, y
end

-- Takes the way the device leans now as level, so the tilt reads `0, 0` while the person keeps holding it that way. Returns `false` and changes nothing without a reading of the accelerometer.
function motion.calibrateTilt()
    local ax, ay, az = motion.acceleration()
    local length = math.sqrt(ax * ax + ay * ay + az * az)
    if not delivered.accelerometer or length <= 0 then
        return false
    end
    level = {ax / length, ay / length, az / length}
    return true
end

-- Makes a device that lies flat face up level again.
function motion.resetTilt()
    level = {0, 0, 1}
end

-- Whether the native part of the plugin runs on this platform.
motion.available = handle.native

return motion
