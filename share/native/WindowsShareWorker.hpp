#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

// A thread of the library that runs its jobs in order, in the multithreaded apartment, where the asynchronous operations of the Windows Runtime may block until they finish. It lives as long as the process.
class WindowsShareWorker final {
  public:
    WindowsShareWorker();

    void post(std::function<void()> job);

  private:
    void run();

    std::mutex mutex;
    std::condition_variable wake;
    std::deque<std::function<void()>> jobs;
    std::thread thread;
};
