#include "LinuxDialogs.hpp"

#include <dlfcn.h>

#include <cctype>
#include <format>
#include <fstream>
#include <thread>

#include "DialogsAnswer.hpp"

const HaylenNativeApi* LinuxDialogs::api = nullptr;
LinuxDialogs::Gtk LinuxDialogs::gtk{};
bool LinuxDialogs::loaded = false;
std::optional<std::pair<std::string, std::string>>& LinuxDialogs::failure = *new std::optional<std::pair<std::string, std::string>>();
void* LinuxDialogs::parent = nullptr;
std::unordered_map<std::uint64_t, LinuxDialogs::Shown>& LinuxDialogs::shown = *new std::unordered_map<std::uint64_t, Shown>();

void LinuxDialogs::use(const HaylenNativeApi& value) noexcept {
    api = &value;
}

void LinuxDialogs::show(std::uint64_t call, DialogsRequest request) {
    if (!load()) {
        DialogsAnswer::fail(call, failure->first, failure->second);
        return;
    }
    if (request.method == DialogsRequest::Method::Message) {
        showMessage(call, std::move(request));
        return;
    }
    showChooser(call, std::move(request));
}

// A message is a widget, which GTK destroys, while a file chooser is an object that the dialogs own.
void LinuxDialogs::cancel(std::uint64_t call) {
    const auto found = shown.find(call);
    if (found == shown.end()) {
        return;
    }
    void* dialog = found->second.dialog;
    const bool chooser = found->second.chooser;
    shown.erase(found);
    if (chooser) {
        gtk.destroyChooser(dialog);
        gtk.unref(dialog);
        return;
    }
    gtk.destroyWidget(dialog);
}

// GTK draws with X11 like the window of the app, even in a Wayland session, so its dialogs can stay over that window, and it leaves the locale of the process alone, which Lua formats numbers with.
bool LinuxDialogs::load() {
    if (loaded || failure) {
        return loaded;
    }
    void* library = dlopen("libgtk-3.so.0", RTLD_NOW | RTLD_LOCAL);
    if (library == nullptr) {
        failure = {"unsupported", "The dialogs of Linux need GTK 3, and the library \"libgtk-3.so.0\" could not be loaded."};
        return false;
    }
    if (!findFunctions(library)) {
        failure = {"unsupported", "The dialogs of Linux need GTK 3.20 or later."};
        return false;
    }

    gtk.setAllowedBackends("x11");
    gtk.disableSetlocale();
    if (gtk.initCheck(nullptr, nullptr) == 0) {
        failure = {"failed", "GTK 3 could not connect to the display of the app."};
        return false;
    }
    loaded = true;
    return true;
}

// The library of GTK finds the functions of GDK, GObject and GLib through its dependencies.
bool LinuxDialogs::findFunctions(void* library) {
    bool found = true;
    found = find(library, gtk.setAllowedBackends, "gdk_set_allowed_backends") && found;
    found = find(library, gtk.disableSetlocale, "gtk_disable_setlocale") && found;
    found = find(library, gtk.initCheck, "gtk_init_check") && found;
    found = find(library, gtk.newMessageDialog, "gtk_message_dialog_new") && found;
    found = find(library, gtk.setSecondaryText, "gtk_message_dialog_format_secondary_text") && found;
    found = find(library, gtk.addButton, "gtk_dialog_add_button") && found;
    found = find(library, gtk.setDefaultResponse, "gtk_dialog_set_default_response") && found;
    found = find(library, gtk.realize, "gtk_widget_realize") && found;
    found = find(library, gtk.getWindow, "gtk_widget_get_window") && found;
    found = find(library, gtk.showWidget, "gtk_widget_show") && found;
    found = find(library, gtk.destroyWidget, "gtk_widget_destroy") && found;
    found = find(library, gtk.getDefaultDisplay, "gdk_display_get_default") && found;
    found = find(library, gtk.newForeignWindow, "gdk_x11_window_foreign_new_for_display") && found;
    found = find(library, gtk.setTransientFor, "gdk_window_set_transient_for") && found;
    found = find(library, gtk.newChooser, "gtk_file_chooser_native_new") && found;
    found = find(library, gtk.setChooserModal, "gtk_native_dialog_set_modal") && found;
    found = find(library, gtk.showChooser, "gtk_native_dialog_show") && found;
    found = find(library, gtk.destroyChooser, "gtk_native_dialog_destroy") && found;
    found = find(library, gtk.setSelectMultiple, "gtk_file_chooser_set_select_multiple") && found;
    found = find(library, gtk.setCurrentName, "gtk_file_chooser_set_current_name") && found;
    found = find(library, gtk.setCurrentFolder, "gtk_file_chooser_set_current_folder") && found;
    found = find(library, gtk.setOverwriteConfirmation, "gtk_file_chooser_set_do_overwrite_confirmation") && found;
    found = find(library, gtk.getFilenames, "gtk_file_chooser_get_filenames") && found;
    found = find(library, gtk.addFilter, "gtk_file_chooser_add_filter") && found;
    found = find(library, gtk.newFilter, "gtk_file_filter_new") && found;
    found = find(library, gtk.setFilterName, "gtk_file_filter_set_name") && found;
    found = find(library, gtk.addPattern, "gtk_file_filter_add_pattern") && found;
    found = find(library, gtk.addMimeType, "gtk_file_filter_add_mime_type") && found;
    found = find(library, gtk.getSpecialFolder, "g_get_user_special_dir") && found;
    found = find(library, gtk.connect, "g_signal_connect_data") && found;
    found = find(library, gtk.unref, "g_object_unref") && found;
    found = find(library, gtk.freeMemory, "g_free") && found;
    found = find(library, gtk.freeList, "g_slist_free") && found;
    return found;
}

template <typename Function> bool LinuxDialogs::find(void* library, Function& function, const char* name) {
    function = reinterpret_cast<Function>(dlsym(library, name));
    return function != nullptr;
}

// The title leads the message in bold where there is one, and the buttons answer with their number.
void LinuxDialogs::showMessage(std::uint64_t call, DialogsRequest request) {
    int type = kInfoMessage;
    switch (request.kind) {
    case DialogsRequest::Kind::Info:
        break;
    case DialogsRequest::Kind::Warning:
        type = kWarningMessage;
        break;
    case DialogsRequest::Kind::Error:
        type = kErrorMessage;
        break;
    }
    const bool titled = !request.title.empty();
    void* dialog = gtk.newMessageDialog(nullptr, kModal, type, kNoButtons, "%s", titled ? request.title.c_str() : request.text.c_str());
    if (titled) {
        gtk.setSecondaryText(dialog, "%s", request.text.c_str());
    }
    for (std::size_t index = 0; index < request.buttons.size(); ++index) {
        gtk.addButton(dialog, request.buttons[index].c_str(), static_cast<int>(index) + 1);
    }
    gtk.setDefaultResponse(dialog, 1);
    gtk.connect(dialog, "response", reinterpret_cast<void (*)()>(&messageResponded), nullptr, nullptr, 0);
    shown.emplace(call, Shown{.dialog = dialog, .chooser = false, .request = std::move(request)});

    gtk.realize(dialog);
    placeOverApp(dialog);
    gtk.showWidget(dialog);
}

// Every chooser is a file chooser of an action, and the pickers of files and of a place to save take the filters of the app.
void LinuxDialogs::showChooser(std::uint64_t call, DialogsRequest request) {
    const DialogsRequest::Method method = request.method;
    const int action = getAction(method);
    void* chooser = gtk.newChooser(request.title.empty() ? nullptr : request.title.c_str(), nullptr, action, nullptr, nullptr);
    if (action == kOpenAction) {
        gtk.setSelectMultiple(chooser, request.multiple ? 1 : 0);
    }
    if (method == DialogsRequest::Method::SaveFile) {
        gtk.setCurrentName(chooser, request.name.c_str());
        gtk.setOverwriteConfirmation(chooser, 1);
    }
    if (method == DialogsRequest::Method::OpenPhotos) {
        addImageFilter(chooser);
    } else {
        addFilters(chooser, request.filters);
    }

    gtk.setChooserModal(chooser, 1);
    gtk.connect(chooser, "response", reinterpret_cast<void (*)()>(&chooserResponded), nullptr, nullptr, 0);
    shown.emplace(call, Shown{.dialog = chooser, .chooser = true, .request = std::move(request)});
    gtk.showChooser(chooser);
}

// The pickers of files and of photos open files, and only a save and a folder take actions of their own.
int LinuxDialogs::getAction(DialogsRequest::Method method) noexcept {
    if (method == DialogsRequest::Method::SaveFile) {
        return kSaveAction;
    }
    if (method == DialogsRequest::Method::OpenFolder) {
        return kFolderAction;
    }
    return kOpenAction;
}

void LinuxDialogs::addFilters(void* chooser, const std::vector<DialogsRequest::Filter>& filters) {
    for (const DialogsRequest::Filter& filter : filters) {
        void* chooserFilter = gtk.newFilter();
        gtk.setFilterName(chooserFilter, filter.name.c_str());
        for (const std::string& extension : filter.extensions) {
            gtk.addPattern(chooserFilter, toPattern(extension).c_str());
        }
        gtk.addFilter(chooser, chooserFilter);
    }
}

// The photos of Linux are image files, so the chooser of images opens in the Pictures folder of the person.
void LinuxDialogs::addImageFilter(void* chooser) {
    void* images = gtk.newFilter();
    gtk.setFilterName(images, "Images");
    gtk.addMimeType(images, "image/*");
    gtk.addFilter(chooser, images);
    const char* pictures = gtk.getSpecialFolder(kPicturesFolder);
    if (pictures != nullptr) {
        gtk.setCurrentFolder(chooser, pictures);
    }
}

// The message stays over the window of the app, whose GDK wrapper lives as long as the process.
void LinuxDialogs::placeOverApp(void* dialog) {
    HaylenNativeWindow app{};
    if (parent == nullptr && api->getWindow(&app) != 0) {
        parent = gtk.newForeignWindow(gtk.getDefaultDisplay(), static_cast<unsigned long>(reinterpret_cast<std::uintptr_t>(app.handle)));
    }
    if (parent != nullptr) {
        gtk.setTransientFor(gtk.getWindow(dialog), parent);
    }
}

// Escape, the close button of the window and the window manager answer with negative responses, which dismiss the message.
void LinuxDialogs::messageResponded(void* dialog, int response, void*) {
    const auto taken = take(dialog);
    gtk.destroyWidget(dialog);
    if (!taken) {
        return;
    }
    if (response > 0) {
        DialogsAnswer::button(taken->first, static_cast<std::size_t>(response));
        return;
    }
    DialogsAnswer::dismissed(taken->first);
}

void LinuxDialogs::chooserResponded(void* chooser, int response, void*) {
    auto taken = take(chooser);
    if (!taken) {
        return;
    }
    const std::vector<std::string> files = response == kAccept ? readFiles(chooser) : std::vector<std::string>();
    gtk.destroyChooser(chooser);
    gtk.unref(chooser);
    auto& [call, dialog] = *taken;
    if (files.empty()) {
        DialogsAnswer::dismissed(call);
        return;
    }

    if (dialog.request.method == DialogsRequest::Method::SaveFile) {
        writeFile(call, files.front(), std::move(dialog.request.bytes));
        return;
    }
    if (dialog.request.method == DialogsRequest::Method::OpenFolder) {
        DialogsAnswer::folder(call, files.front());
        return;
    }

    std::vector<DialogsAnswer::File> picked;
    for (const std::string& file : files) {
        picked.push_back({.name = std::filesystem::path(file).filename().string(), .path = file});
    }
    DialogsAnswer::files(call, picked);
}

std::optional<std::pair<std::uint64_t, LinuxDialogs::Shown>> LinuxDialogs::take(void* dialog) {
    for (auto entry = shown.begin(); entry != shown.end(); ++entry) {
        if (entry->second.dialog == dialog) {
            std::pair<std::uint64_t, Shown> taken{entry->first, std::move(entry->second)};
            shown.erase(entry);
            return taken;
        }
    }
    return std::nullopt;
}

// The chooser returns a list of paths that belong to the caller, which frees every path and the list.
std::vector<std::string> LinuxDialogs::readFiles(void* chooser) {
    std::vector<std::string> files;
    List* list = gtk.getFilenames(chooser);
    for (List* node = list; node != nullptr; node = node->next) {
        files.emplace_back(static_cast<const char*>(node->data));
        gtk.freeMemory(node->data);
    }
    gtk.freeList(list);
    return files;
}

// The bytes may be many, so they are written on a thread of their own, which answers the dialog.
void LinuxDialogs::writeFile(std::uint64_t call, const std::filesystem::path& path, std::vector<std::uint8_t> bytes) {
    // clang-format off
    std::thread([call, path, bytes = std::move(bytes)] {
        std::ofstream stream(path, std::ios::binary | std::ios::trunc);
        stream.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        stream.close();
        const std::string name = path.filename().string();
        if (!stream) {
            DialogsAnswer::fail(call, "failed", std::format("The file \"{}\" could not be written.", name));
            return;
        }
        DialogsAnswer::saved(call, {.name = name, .path = path.string()});
    }).detach();
    // clang-format on
}

std::string LinuxDialogs::toPattern(std::string_view extension) {
    std::string pattern = "*.";
    for (const char character : extension) {
        const auto code = static_cast<unsigned char>(character);
        if (code < 128 && std::isalpha(code) != 0) {
            pattern += {'[', static_cast<char>(std::tolower(code)), static_cast<char>(std::toupper(code)), ']'};
        } else {
            pattern += character;
        }
    }
    return pattern;
}
