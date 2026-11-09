#include "WindowsWorker.hpp"

#include <utility>

#include <windows.h>

#include <mfapi.h>
#include <roapi.h>

WindowsWorker::WindowsWorker() : thread(&WindowsWorker::run, this) {}

void WindowsWorker::post(std::function<void()> job) {
    {
        const std::lock_guard<std::mutex> guard(mutex);
        jobs.push_back(std::move(job));
    }
    wake.notify_one();
}

void WindowsWorker::run() {
    RoInitialize(RO_INIT_MULTITHREADED);
    MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
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
