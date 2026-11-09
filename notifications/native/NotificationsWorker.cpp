#include "NotificationsWorker.hpp"

#include <utility>

#include <winrt/Windows.Foundation.h>

NotificationsWorker::NotificationsWorker() : thread(&NotificationsWorker::run, this) {}

void NotificationsWorker::post(std::function<void()> job) {
    {
        const std::lock_guard<std::mutex> guard(mutex);
        jobs.push_back(std::move(job));
    }
    wake.notify_one();
}

void NotificationsWorker::run() {
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
