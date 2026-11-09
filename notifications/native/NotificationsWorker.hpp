#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

// A thread of the library that runs its jobs in order, in the multithreaded apartment, where the notifier of Windows and COM work. It lives as long as the process.
class NotificationsWorker final {
  public:
    NotificationsWorker();

    void post(std::function<void()> job);

  private:
    void run();

    std::mutex mutex;
    std::condition_variable wake;
    std::deque<std::function<void()>> jobs;
    std::thread thread;
};
