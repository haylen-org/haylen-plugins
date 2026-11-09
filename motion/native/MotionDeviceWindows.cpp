// The motion sensors of Windows: the accelerometer, the gyrometer and the relative orientation sensor of tablets and convertibles through `Windows.Devices.Sensors`, called with C++/WinRT, whose headers come with the Windows SDK. Windows gates none of them behind a permission for desktop apps, so the permission `motion` tells whether the computer has one of them. A thread of the library alone starts and stops the sensors, which deliver their readings on threads of Windows in the axes of the device in its native orientation, with the quarter turns of the display that shows the app.

#define NOMINMAX
#include <windows.h>

#include <winrt/Windows.Devices.Sensors.h>
#include <winrt/Windows.Foundation.h>

#include "MotionDevice.hpp"
#include "MotionPlugin.hpp"

#include <algorithm>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <numbers>
#include <optional>
#include <string_view>
#include <thread>

using winrt::Windows::Devices::Sensors::Accelerometer;
using winrt::Windows::Devices::Sensors::AccelerometerReadingChangedEventArgs;
using winrt::Windows::Devices::Sensors::Gyrometer;
using winrt::Windows::Devices::Sensors::GyrometerReadingChangedEventArgs;
using winrt::Windows::Devices::Sensors::OrientationSensor;
using winrt::Windows::Devices::Sensors::OrientationSensorReadingChangedEventArgs;
using winrt::Windows::Devices::Sensors::SensorReadingType;

struct MotionDevice::System {
    // A thread of the library that runs its jobs in order, in the multithreaded apartment, where the sensors of the Windows Runtime open.
    class Worker final {
      public:
        Worker() : thread(&Worker::run, this) {}

        void post(std::function<void()> job) {
            {
                const std::lock_guard<std::mutex> guard(mutex);
                jobs.push_back(std::move(job));
            }
            wake.notify_one();
        }

      private:
        void run() {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            for (;;) {
                std::function<void()> job;
                {
                    std::unique_lock<std::mutex> guard(mutex);
                    wake.wait(guard, [this] { return !jobs.empty(); });
                    job = std::move(jobs.front());
                    jobs.pop_front();
                }
                job();
            }
        }

        std::mutex mutex;
        std::condition_variable wake;
        std::deque<std::function<void()>> jobs;
        std::thread thread;
    };

    // The sensors of the computer, which Windows gives as their defaults, or as null where the computer lacks one.
    struct Sensors {
        Accelerometer accelerometer{nullptr};
        Gyrometer gyroscope{nullptr};
        OrientationSensor attitude{nullptr};

        static Sensors find() {
            Sensors sensors;
            sensors.accelerometer = Accelerometer::GetDefault();
            sensors.gyroscope = Gyrometer::GetDefault();
            sensors.attitude = OrientationSensor::GetDefault(SensorReadingType::Relative);
            return sensors;
        }

        [[nodiscard]] bool has(std::string_view name) const {
            if (name == "accelerometer") {
                return accelerometer != nullptr;
            }
            if (name == "gyroscope") {
                return gyroscope != nullptr;
            }
            if (name == "attitude") {
                return attitude != nullptr;
            }
            return false;
        }

        [[nodiscard]] bool empty() const {
            return accelerometer == nullptr && gyroscope == nullptr && attitude == nullptr;
        }
    };

    // The sensors that run for a session, whose readings reach the app while their revokers live.
    struct Run {
        std::int64_t session = 0;
        Sensors sensors;
        Accelerometer::ReadingChanged_revoker accelerations;
        Gyrometer::ReadingChanged_revoker rotations;
        OrientationSensor::ReadingChanged_revoker attitudes;
    };

    // The acceleration of gravity in meters per second squared, since Windows measures accelerations in units of it.
    static constexpr double kGravity = 9.80665;
    static constexpr double kRadiansPerDegree = std::numbers::pi / 180;

    // The words of a list of sensor names, such as "accelerometer" and "gyroscope".
    static std::string listNames(const std::vector<std::string>& names) {
        std::string text;
        for (std::size_t index = 0; index < names.size(); ++index) {
            if (index > 0) {
                text += index + 1 == names.size() ? " and " : ", ";
            }
            text += "\"" + names[index] + "\"";
        }
        return text;
    }

    void start(std::uint64_t call, std::int64_t started, double rate, const std::vector<std::string>& names) {
        const Sensors sensors = Sensors::find();
        std::vector<std::string> absent;
        for (const std::string& name : names) {
            if (!sensors.has(name)) {
                absent.push_back(name);
            }
        }
        if (sensors.empty()) {
            plugin.fail(call, "This computer has no motion sensors.", "unsupported");
            return;
        }
        if (!absent.empty()) {
            const std::string_view noun = absent.size() == 1 ? "sensor " : "sensors ";
            plugin.fail(call, "The computer has no motion " + std::string(noun) + listNames(absent) + ".", "unsupported");
            return;
        }
        if (watched != started) {
            plugin.fail(call, "The app stopped the motion sensors before they started.", "cancelled");
            return;
        }

        stopSensors();
        Run& running = current.emplace();
        running.session = started;
        const auto interval = static_cast<std::uint32_t>(std::lround(1000.0 / rate));
        for (const std::string& name : names) {
            open(running, sensors, name, interval);
        }
        plugin.succeed(call, {{"sensors", names}});
    }

    // Starts one sensor at the interval that the rate asks for, kept within what the sensor delivers. Windows measures the acceleration of gravity as the pull toward the ground, so the readings turn around into the push that holds the device up, as the other platforms measure it, and the rotation turns from degrees into radians.
    void open(Run& running, const Sensors& sensors, const std::string& name, std::uint32_t interval) {
        const std::int64_t session = running.session;
        const System* owner = this;
        if (name == "accelerometer") {
            running.sensors.accelerometer = sensors.accelerometer;
            sensors.accelerometer.ReportInterval(std::max(interval, sensors.accelerometer.MinimumReportInterval()));
            // clang-format off
            running.accelerations = sensors.accelerometer.ReadingChanged(winrt::auto_revoke, [owner, session](const Accelerometer&, const AccelerometerReadingChangedEventArgs& args) {
                const auto reading = args.Reading();
                owner->send(session, "accelerometer", -reading.AccelerationX() * kGravity, -reading.AccelerationY() * kGravity, -reading.AccelerationZ() * kGravity, std::nullopt);
            });
            // clang-format on
            return;
        }
        if (name == "gyroscope") {
            running.sensors.gyroscope = sensors.gyroscope;
            sensors.gyroscope.ReportInterval(std::max(interval, sensors.gyroscope.MinimumReportInterval()));
            // clang-format off
            running.rotations = sensors.gyroscope.ReadingChanged(winrt::auto_revoke, [owner, session](const Gyrometer&, const GyrometerReadingChangedEventArgs& args) {
                const auto reading = args.Reading();
                owner->send(session, "gyroscope", reading.AngularVelocityX() * kRadiansPerDegree, reading.AngularVelocityY() * kRadiansPerDegree, reading.AngularVelocityZ() * kRadiansPerDegree, std::nullopt);
            });
            // clang-format on
            return;
        }
        running.sensors.attitude = sensors.attitude;
        sensors.attitude.ReportInterval(std::max(interval, sensors.attitude.MinimumReportInterval()));
        // clang-format off
        running.attitudes = sensors.attitude.ReadingChanged(winrt::auto_revoke, [owner, session](const OrientationSensor&, const OrientationSensorReadingChangedEventArgs& args) {
            const auto quaternion = args.Reading().Quaternion();
            owner->send(session, "attitude", quaternion.X(), quaternion.Y(), quaternion.Z(), quaternion.W());
        });
        // clang-format on
    }

    // Stops every sensor, after which Windows sends no reading, and restores the interval that each one had by default.
    void stopSensors() {
        if (!current) {
            return;
        }
        Run& running = *current;
        running.accelerations.revoke();
        running.rotations.revoke();
        running.attitudes.revoke();
        if (running.sensors.accelerometer) {
            running.sensors.accelerometer.ReportInterval(0);
        }
        if (running.sensors.gyroscope) {
            running.sensors.gyroscope.ReportInterval(0);
        }
        if (running.sensors.attitude) {
            running.sensors.attitude.ReportInterval(0);
        }
        current.reset();
    }

    // A desktop app is in the background while its window is minimized, and the plugin sends no readings then.
    void send(std::int64_t session, std::string_view sensor, double x, double y, double z, std::optional<double> w) const {
        HaylenNativeWindow window{};
        if (plugin.getApi().getWindow(&window) != 0 && window.handle != nullptr && IsIconic(static_cast<HWND>(window.handle))) {
            return;
        }

        MotionPlugin::Json reading = {{"session", session}, {"sensor", sensor}, {"x", x}, {"y", y}, {"z", z}};
        if (w) {
            reading["w"] = *w;
        }
        reading["turns"] = turns();
        plugin.emit("motion.reading", reading, HAYLEN_NATIVE_EMIT_BATCHED);
    }

    // The quarter turns counterclockwise of the device while its display keeps the app upright. Windows tells how far the image of the display turns counterclockwise from the native orientation of the panel, which is the opposite turn of the device.
    int turns() const {
        HaylenNativeWindow window{};
        if (plugin.getApi().getWindow(&window) == 0 || window.handle == nullptr) {
            return 0;
        }
        MONITORINFOEXW monitor{};
        monitor.cbSize = sizeof(monitor);
        DEVMODEW mode{};
        mode.dmSize = sizeof(mode);
        const HMONITOR display = MonitorFromWindow(static_cast<HWND>(window.handle), MONITOR_DEFAULTTONEAREST);
        if (!GetMonitorInfoW(display, &monitor) || !EnumDisplaySettingsExW(monitor.szDevice, ENUM_CURRENT_SETTINGS, &mode, 0)) {
            return 0;
        }
        return static_cast<int>((4 - mode.dmDisplayOrientation % 4) % 4);
    }

    const MotionPlugin& plugin;
    // Only the worker touches the sessions and the sensors, which live as long as the process, since Windows may still deliver readings while the process exits.
    Worker worker;
    std::int64_t watched = 0;
    std::uint64_t watch = 0;
    std::optional<Run> current;
};

MotionDevice::MotionDevice(const MotionPlugin& owner) : system(new System{.plugin = owner}) {}

MotionDevice::~MotionDevice() = default;

// Answers the permission `motion`, which Windows grants every desktop app on a computer with a motion sensor and asks no one for.
void MotionDevice::permission(std::uint64_t call) {
    System* sensors = system.get();
    // clang-format off
    sensors->worker.post([sensors, call] {
        if (System::Sensors::find().empty()) {
            sensors->plugin.fail(call, "This computer has no motion sensors.", "unsupported");
            return;
        }
        sensors->plugin.succeed(call, MotionPlugin::Json("granted"));
    });
    // clang-format on
}

// Holds the call while the sensors of the session run, until the app gives it up.
void MotionDevice::watch(std::uint64_t call, std::int64_t session) {
    System* sensors = system.get();
    // clang-format off
    sensors->worker.post([sensors, call, session] {
        sensors->stopSensors();
        sensors->watched = session;
        sensors->watch = call;
    });
    // clang-format on
}

void MotionDevice::cancelWatch(std::uint64_t call) {
    System* sensors = system.get();
    // clang-format off
    sensors->worker.post([sensors, call] {
        if (sensors->watch != call) {
            return;
        }
        sensors->stopSensors();
        sensors->watched = 0;
        sensors->watch = 0;
    });
    // clang-format on
}

void MotionDevice::start(std::uint64_t call, std::int64_t session, double rate, std::vector<std::string> sensors) {
    System* device = system.get();
    // clang-format off
    device->worker.post([device, call, session, rate, names = std::move(sensors)] {
        try {
            device->start(call, session, rate, names);
        } catch (const winrt::hresult_error& error) {
            device->plugin.fail(call, "Windows did not start the motion sensors: " + winrt::to_string(error.message()), "failed");
        }
    });
    // clang-format on
}
