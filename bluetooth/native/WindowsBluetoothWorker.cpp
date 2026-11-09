#include "WindowsBluetoothWorker.hpp"

#include <utility>

#include <winrt/base.h>

WindowsBluetoothWorker::WindowsBluetoothWorker() : thread(&WindowsBluetoothWorker::run, this) {}

void WindowsBluetoothWorker::post(std::function<void()> job) {
    postAfter(Clock::duration::zero(), std::move(job));
}

void WindowsBluetoothWorker::postAfter(Clock::duration delay, std::function<void()> job) {
    {
        const std::lock_guard<std::mutex> guard(mutex);
        jobs.emplace(Clock::now() + delay, std::move(job));
    }
    wake.notify_one();
}

void WindowsBluetoothWorker::run() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    for (;;) {
        std::function<void()> job;
        {
            std::unique_lock<std::mutex> guard(mutex);
            // clang-format off
            wake.wait(guard, [this] { return !jobs.empty(); });
            while (jobs.begin()->first > Clock::now()) {
                const Clock::time_point due = jobs.begin()->first;
                wake.wait_until(guard, due, [this, due] { return jobs.begin()->first < due; });
            }
            // clang-format on
            job = std::move(jobs.begin()->second);
            jobs.erase(jobs.begin());
        }
        job();
    }
}
