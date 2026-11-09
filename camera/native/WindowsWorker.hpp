#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

// A thread of the library that runs its jobs in order, in the multithreaded apartment of COM, where Media Foundation, WIC and the Windows Runtime work. It lives as long as the process.
class WindowsWorker final {
  public:
    WindowsWorker();

    WindowsWorker(const WindowsWorker&) = delete;
    WindowsWorker& operator=(const WindowsWorker&) = delete;

    void post(std::function<void()> job);

  private:
    void run();

    std::mutex mutex;
    std::condition_variable wake;
    std::deque<std::function<void()>> jobs;
    std::thread thread;
};
