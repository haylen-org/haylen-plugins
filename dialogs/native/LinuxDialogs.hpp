#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

#include "DialogsRequest.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The dialogs of Linux through GTK 3, which the library loads with the first dialog, so apps run on systems without it, where every dialog fails with the code `unsupported`. A message is a GTK message dialog over the window of the app, and the pickers are GTK file choosers, which the desktop portal shows where it runs. GTK runs on the frame thread, where the engine dispatches the default main context of GLib once per frame, so the dialogs answer there, and a save writes its data on a thread of its own.
class LinuxDialogs final {
  public:
    static void use(const HaylenNativeApi& value) noexcept;

    // Called on the frame thread.
    static void show(std::uint64_t call, DialogsRequest request);

    // Closes a dialog that the app gave up, which answers nothing.
    static void cancel(std::uint64_t call);

  private:
    static constexpr int kInfoMessage = 0;
    static constexpr int kWarningMessage = 1;
    static constexpr int kErrorMessage = 3;
    static constexpr int kModal = 1;
    static constexpr int kNoButtons = 0;
    static constexpr int kAccept = -3;
    static constexpr int kOpenAction = 0;
    static constexpr int kSaveAction = 1;
    static constexpr int kFolderAction = 2;
    static constexpr int kPicturesFolder = 4;

    // A dialog that shows: a message, which is a widget, or a file chooser, which is an object of its own and keeps the request of a save.
    struct Shown {
        void* dialog = nullptr;
        bool chooser = false;
        DialogsRequest request;
    };

    // A list of GLib, which the file choosers return their files in.
    struct List {
        void* data;
        List* next;
    };

    // The functions of GTK 3, GDK, GObject and GLib that the dialogs use.
    struct Gtk {
        void (*setAllowedBackends)(const char* backends);
        void (*disableSetlocale)();
        int (*initCheck)(int* argc, char*** argv);
        void* (*newMessageDialog)(void* parent, int flags, int type, int buttons, const char* format, ...);
        void (*setSecondaryText)(void* dialog, const char* format, ...);
        void* (*addButton)(void* dialog, const char* text, int response);
        void (*setDefaultResponse)(void* dialog, int response);
        void (*realize)(void* widget);
        void* (*getWindow)(void* widget);
        void (*showWidget)(void* widget);
        void (*destroyWidget)(void* widget);
        void* (*getDefaultDisplay)();
        void* (*newForeignWindow)(void* display, unsigned long window);
        void (*setTransientFor)(void* window, void* parent);
        void* (*newChooser)(const char* title, void* parent, int action, const char* acceptLabel, const char* cancelLabel);
        void (*setChooserModal)(void* chooser, int modal);
        void (*showChooser)(void* chooser);
        void (*destroyChooser)(void* chooser);
        void (*setSelectMultiple)(void* chooser, int multiple);
        void (*setCurrentName)(void* chooser, const char* name);
        int (*setCurrentFolder)(void* chooser, const char* folder);
        void (*setOverwriteConfirmation)(void* chooser, int confirm);
        List* (*getFilenames)(void* chooser);
        void (*addFilter)(void* chooser, void* filter);
        void* (*newFilter)();
        void (*setFilterName)(void* filter, const char* name);
        void (*addPattern)(void* filter, const char* pattern);
        void (*addMimeType)(void* filter, const char* type);
        const char* (*getSpecialFolder)(int folder);
        unsigned long (*connect)(void* instance, const char* signal, void (*handler)(), void* data, void (*release)(void*, void*), int flags);
        void (*unref)(void* object);
        void (*freeMemory)(void* memory);
        void (*freeList)(List* list);
    };

    static const HaylenNativeApi* api;
    static Gtk gtk;
    static bool loaded;
    static std::optional<std::pair<std::string, std::string>>& failure;
    static void* parent;
    static std::unordered_map<std::uint64_t, Shown>& shown;

    [[nodiscard]] static bool load();
    [[nodiscard]] static bool findFunctions(void* library);
    template <typename Function> static bool find(void* library, Function& function, const char* name);
    static void showMessage(std::uint64_t call, DialogsRequest request);
    static void showChooser(std::uint64_t call, DialogsRequest request);
    [[nodiscard]] static int getAction(DialogsRequest::Method method) noexcept;
    static void addFilters(void* chooser, const std::vector<DialogsRequest::Filter>& filters);
    static void addImageFilter(void* chooser);
    static void placeOverApp(void* dialog);
    static void messageResponded(void* dialog, int response, void* data);
    static void chooserResponded(void* chooser, int response, void* data);
    [[nodiscard]] static std::optional<std::pair<std::uint64_t, Shown>> take(void* dialog);
    [[nodiscard]] static std::vector<std::string> readFiles(void* chooser);
    static void writeFile(std::uint64_t call, const std::filesystem::path& path, std::vector<std::uint8_t> bytes);

    // Returns `*.[pP][nN][gG]` for `png`, a pattern that ignores case, as the file dialogs of the other desktops do.
    [[nodiscard]] static std::string toPattern(std::string_view extension);
};
