#pragma once

#include <windows.h>

#include <filesystem>
#include <optional>
#include <string>

// The shortcut of the Start menu that gives the app its AppUserModelID, which the installer of the app creates, with the toast activator that it names.
class NotificationsShortcut final {
  public:
    // Finds the shortcut of the app among the shortcuts of the Start menu of the person and of every user, and returns the class of its toast activator, which may be null.
    [[nodiscard]] static std::optional<GUID> find(const std::wstring& identifier);

    // Whether COM knows how to start the app for the class, as a local server.
    [[nodiscard]] static bool isRegistered(const GUID& activator);

  private:
    // The class of the toast activator of a shortcut whose AppUserModelID is the identifier, the null class for one without an activator, or nothing for any other shortcut.
    [[nodiscard]] static std::optional<GUID> read(const std::filesystem::path& file, const std::wstring& identifier);
};
