#include "WindowsLocationWorker.hpp"

#include <utility>

#include <windows.h>

#include <roapi.h>

WindowsLocationWorker::WindowsLocationWorker() : thread(&WindowsLocationWorker::run, this) {}

void WindowsLocationWorker::post(std::function<void()> job) {
    {
        const std::lock_guard guard(mutex);
        jobs.push_back(std::move(job));
    }
    wake.notify_one();
}

void WindowsLocationWorker::run() {
    RoInitialize(RO_INIT_MULTITHREADED);
    for (;;) {
        std::function<void()> job;
        {
            std::unique_lock guard(mutex);
            wake.wait(guard, [this] { return !jobs.empty(); });
            job = std::move(jobs.front());
            jobs.pop_front();
        }
        job();
    }
}
