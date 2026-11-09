#include "WindowsShareWorker.hpp"

#include <utility>

#include <winrt/base.h>

WindowsShareWorker::WindowsShareWorker() : thread(&WindowsShareWorker::run, this) {}

void WindowsShareWorker::post(std::function<void()> job) {
    {
        const std::scoped_lock lock(mutex);
        jobs.push_back(std::move(job));
    }
    wake.notify_one();
}

void WindowsShareWorker::run() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    for (;;) {
        std::function<void()> job;
        {
            std::unique_lock lock(mutex);
            wake.wait(lock, [this] { return !jobs.empty(); });
            job = std::move(jobs.front());
            jobs.pop_front();
        }
        job();
    }
}
