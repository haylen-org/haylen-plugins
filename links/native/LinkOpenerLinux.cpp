#include "LinkOpener.hpp"

#include <array>
#include <system_error>
#include <thread>
#include <utility>

#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

// Starts `xdg-open` and waits for it on a thread of its own, so the frame thread never waits. Its status tells whether an app took the url.
void LinkOpener::open(std::string url, std::function<void(Answer)> reply) {
    // clang-format off
    auto wait = [url = std::move(url), reply]() mutable {
        std::string command = "xdg-open";
        std::array<char*, 3> arguments{command.data(), url.data(), nullptr};
        pid_t child = 0;
        if (posix_spawnp(&child, command.c_str(), nullptr, nullptr, arguments.data(), environ) != 0) {
            reply(Answer::MissingCommand);
            return;
        }

        int status = 0;
        const bool opened = waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0;
        reply(opened ? Answer::Opened : Answer::NoApp);
    };
    // clang-format on

    try {
        std::thread(std::move(wait)).detach();
    } catch (const std::system_error&) {
        reply(Answer::NoThread);
    }
}
