#pragma once

#include <chrono>
#include <condition_variable>
#include <functional>
#include <map>
#include <mutex>
#include <thread>

// A thread of the library that runs its jobs in order, at once or once their delay passed, in the multithreaded apartment, where the asynchronous operations of the Windows Runtime may block until they finish. It lives as long as the process.
class WindowsBluetoothWorker final {
  public:
    using Clock = std::chrono::steady_clock;

    WindowsBluetoothWorker();

    void post(std::function<void()> job);
    void postAfter(Clock::duration delay, std::function<void()> job);

  private:
    void run();

    std::mutex mutex;
    std::condition_variable wake;
    std::multimap<Clock::time_point, std::function<void()>> jobs;
    std::thread thread;
};
