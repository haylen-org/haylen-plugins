#include "LinuxNotifications.hpp"

#include <cstring>
#include <thread>
#include <utility>

int LinuxNotifications::initialize(const HaylenNativeApi* engine) {
    if (engine->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    auto* library = new LinuxNotifications(*engine);
    library->connect();

    engine->registerHandler("notifications.show", &LinuxNotifications::handleShow, nullptr, library);
    engine->registerHandler("notifications.showSilent", &LinuxNotifications::handleShow, nullptr, library);
    engine->registerHandler("notifications.close", &LinuxNotifications::handleClose, nullptr, library);
    engine->registerHandler("notifications.permission", &LinuxNotifications::handlePermission, nullptr, library);
    engine->registerHandler("notifications.requestPermission", &LinuxNotifications::handlePermission, nullptr, library);
    engine->registerPlugin("notifications");
    return 0;
}

LinuxNotifications::LinuxNotifications(const HaylenNativeApi& engine) : api(engine) {}

// Shows a notification whose title, body, app name and desktop entry come as the four byte buffers of the call, in that order.
void LinuxNotifications::handleShow(void* user, std::uint64_t call, const char* method, const char*, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    auto& library = *static_cast<LinuxNotifications*>(user);
    if (library.bus == nullptr) {
        library.fail(call, library.busFailure, "unsupported");
        return;
    }
    if (bufferCount != 4) {
        library.fail(call, "The call needs the title, the body, the app name and the desktop entry as four byte buffers.", "invalidParams");
        return;
    }

    const Work work = std::strcmp(method, "notifications.showSilent") == 0 ? Work::ShowSilent : Work::Show;
    auto text = [buffers](std::size_t index) { return std::string(static_cast<const char*>(buffers[index].data), buffers[index].size); };
    std::unique_ptr<Job> job = library.newJob(work, call);
    job->title = text(0);
    job->body = text(1);
    job->appName = text(2);
    job->desktopEntry = text(3);
    library.enqueue(std::move(job));
}

// Closes the notification whose server id the parameters hold as `[id]`, which the Lua module sends without awaiting an answer.
void LinuxNotifications::handleClose(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    auto& library = *static_cast<LinuxNotifications*>(user);
    const Json params = Json::parse(paramsJson, nullptr, false);
    const bool valid = params.is_array() && params.size() == 1 && params[0].is_number_unsigned() && params[0].get<std::uint64_t>() <= UINT32_MAX;
    if (!valid) {
        library.fail(call, "The call needs the server id of the notification as \"[id]\".", "invalidParams");
        return;
    }

    if (library.bus != nullptr) {
        std::unique_ptr<Job> job = library.newJob(Work::Close, call);
        job->serverId = static_cast<dbus_uint32_t>(params[0].get<std::uint64_t>());
        library.enqueue(std::move(job));
    }
    library.succeed(call, Json::object());
}

// Answers the permission `notifications`, which the desktop gives every app while a notification server runs and which shows no prompt, so a request answers the same. A desktop without a server fails the call with the code `unsupported`.
void LinuxNotifications::handlePermission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    auto& library = *static_cast<LinuxNotifications*>(user);
    if (library.bus == nullptr) {
        library.fail(call, library.busFailure, "unsupported");
        return;
    }
    library.enqueue(library.newJob(Work::Permission, call));
}

// Answers the call of a job once the server replied, on the thread of the bus.
void LinuxNotifications::replied(DBusPendingCall* pending, void* user) {
    const auto& job = *static_cast<const Job*>(user);
    const Message reply(dbus_pending_call_steal_reply(pending), &dbus_message_unref);
    job.owner->answer(job, reply.get());
    dbus_pending_call_unref(pending);
}

void LinuxNotifications::releaseJob(void* user) {
    delete static_cast<Job*>(user);
}

// Sends `activated` when the person clicks a notification and `closed` when it goes away, with the id that the server gave it.
DBusHandlerResult LinuxNotifications::filter(DBusConnection*, DBusMessage* message, void* user) {
    const auto& library = *static_cast<const LinuxNotifications*>(user);
    dbus_uint32_t serverId = 0;

    if (dbus_message_is_signal(message, kService, "ActionInvoked")) {
        const char* action = nullptr;
        const bool read = dbus_message_get_args(message, nullptr, DBUS_TYPE_UINT32, &serverId, DBUS_TYPE_STRING, &action, DBUS_TYPE_INVALID);
        if (read && std::strcmp(action, "default") == 0) {
            library.emit("notifications.activated", {{"serverId", serverId}});
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (dbus_message_is_signal(message, kService, "NotificationClosed")) {
        dbus_uint32_t reason = 0;
        if (dbus_message_get_args(message, nullptr, DBUS_TYPE_UINT32, &serverId, DBUS_TYPE_UINT32, &reason, DBUS_TYPE_INVALID)) {
            library.emit("notifications.closed", {{"serverId", serverId}});
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

std::string LinuxNotifications::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}

// Connects to the session bus once, on a connection of its own, so the bus of the window of the engine stays as it is. A failure keeps the reason, which every call then answers.
void LinuxNotifications::connect() {
    dbus_threads_init_default();

    DBusError error;
    dbus_error_init(&error);
    DBusConnection* connection = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
    if (connection == nullptr) {
        busFailure = std::string("The session bus is not reachable, so the desktop shows no notifications: ") + error.message;
        dbus_error_free(&error);
        return;
    }

    dbus_connection_set_exit_on_disconnect(connection, FALSE);
    dbus_bus_add_match(connection, kMatch, nullptr);
    dbus_connection_add_filter(connection, &LinuxNotifications::filter, this, nullptr);
    bus = connection;
    std::thread(&LinuxNotifications::loop, this).detach();
}

// The thread of the bus, which lives as long as the process and ends when the session bus goes away.
void LinuxNotifications::loop() {
    while (dbus_connection_read_write_dispatch(bus, kPollMilliseconds)) {
        std::vector<std::unique_ptr<Job>> jobs;
        {
            const std::lock_guard<std::mutex> guard(lock);
            jobs.swap(queue);
        }
        for (std::unique_ptr<Job>& job : jobs) {
            run(std::move(job));
        }
    }
}

std::unique_ptr<LinuxNotifications::Job> LinuxNotifications::newJob(Work work, std::uint64_t call) {
    return std::make_unique<Job>(Job{.owner = this, .work = work, .call = call, .title = {}, .body = {}, .appName = {}, .desktopEntry = {}, .serverId = 0});
}

void LinuxNotifications::enqueue(std::unique_ptr<Job> job) {
    const std::lock_guard<std::mutex> guard(lock);
    queue.push_back(std::move(job));
}

// Sends a queued job to the bus. A close answers no call, so its reply is not awaited.
void LinuxNotifications::run(std::unique_ptr<Job> job) {
    const Message message = messageOf(*job);
    if (job->work == Work::Close) {
        dbus_message_set_no_reply(message.get(), TRUE);
        dbus_connection_send(bus, message.get(), nullptr);
        return;
    }

    DBusPendingCall* pending = nullptr;
    if (!dbus_connection_send_with_reply(bus, message.get(), &pending, kReplyMilliseconds) || pending == nullptr) {
        failJob(*job, "The session bus is gone, so the notification server cannot be reached.");
        return;
    }
    dbus_pending_call_set_notify(pending, &LinuxNotifications::replied, job.release(), &LinuxNotifications::releaseJob);
}

void LinuxNotifications::answer(const Job& job, DBusMessage* reply) {
    DBusError error;
    dbus_error_init(&error);
    if (reply == nullptr || dbus_set_error_from_message(&error, reply)) {
        const char* reason = error.message != nullptr ? error.message : "the session bus gave no reply.";
        failJob(job, std::string("The notification server did not answer: ") + reason);
        dbus_error_free(&error);
        return;
    }

    if (job.work == Work::Permission) {
        dbus_bool_t running = FALSE;
        dbus_message_get_args(reply, nullptr, DBUS_TYPE_BOOLEAN, &running, DBUS_TYPE_INVALID);
        if (running) {
            succeed(job.call, "granted");
            return;
        }
        fail(job.call, "No notification server runs on the session bus, so the desktop shows no notifications.", "unsupported");
        return;
    }

    dbus_uint32_t serverId = 0;
    dbus_message_get_args(reply, nullptr, DBUS_TYPE_UINT32, &serverId, DBUS_TYPE_INVALID);
    succeed(job.call, {{"serverId", serverId}});
}

void LinuxNotifications::succeed(std::uint64_t call, const Json& result) const {
    const std::string text = write(result);
    api.resolve(call, 1, text.c_str(), nullptr, 0);
}

void LinuxNotifications::fail(std::uint64_t call, std::string_view message, std::string_view code) const {
    const std::string text = write({{"message", message}, {"code", code}});
    api.resolve(call, 0, text.c_str(), nullptr, 0);
}

// A permission that the bus cannot tell fails with the code `unsupported` and the reason, and any other call fails with the code `serverFailed`.
void LinuxNotifications::failJob(const Job& job, const std::string& message) const {
    if (job.work == Work::Permission) {
        fail(job.call, message, "unsupported");
        return;
    }
    fail(job.call, message, "serverFailed");
}

void LinuxNotifications::emit(const char* event, const Json& payload) const {
    const std::string text = write(payload);
    api.emit(event, text.c_str(), nullptr, 0, 0);
}

// Builds the `Notify` call of the server with the action `default`, which the server invokes when the person clicks the notification.
LinuxNotifications::Message LinuxNotifications::notifyMessage(const Job& job) {
    Message message(dbus_message_new_method_call(kService, kPath, kService, "Notify"), &dbus_message_unref);
    const char* appName = job.appName.c_str();
    const char* icon = "";
    const char* title = job.title.c_str();
    const char* body = job.body.c_str();
    const dbus_uint32_t replaces = 0;
    const dbus_int32_t expires = -1;

    DBusMessageIter arguments;
    dbus_message_iter_init_append(message.get(), &arguments);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &appName);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_UINT32, &replaces);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &icon);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &title);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &body);

    DBusMessageIter actions;
    const char* action = "default";
    const char* label = "Open";
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "s", &actions);
    dbus_message_iter_append_basic(&actions, DBUS_TYPE_STRING, &action);
    dbus_message_iter_append_basic(&actions, DBUS_TYPE_STRING, &label);
    dbus_message_iter_close_container(&arguments, &actions);

    // The hint "desktop-entry" names the desktop entry of the app, which the Linux project of Haylen installs under the identifier of the app, so the server shows the name and the icon of the app.
    DBusMessageIter hints;
    DBusMessageIter hint;
    DBusMessageIter value;
    const char* entryKey = "desktop-entry";
    const char* desktopEntry = job.desktopEntry.c_str();
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &hints);
    dbus_message_iter_open_container(&hints, DBUS_TYPE_DICT_ENTRY, nullptr, &hint);
    dbus_message_iter_append_basic(&hint, DBUS_TYPE_STRING, &entryKey);
    dbus_message_iter_open_container(&hint, DBUS_TYPE_VARIANT, "s", &value);
    dbus_message_iter_append_basic(&value, DBUS_TYPE_STRING, &desktopEntry);
    dbus_message_iter_close_container(&hint, &value);
    dbus_message_iter_close_container(&hints, &hint);

    if (job.work == Work::ShowSilent) {
        const char* soundKey = "suppress-sound";
        const dbus_bool_t suppress = TRUE;
        dbus_message_iter_open_container(&hints, DBUS_TYPE_DICT_ENTRY, nullptr, &hint);
        dbus_message_iter_append_basic(&hint, DBUS_TYPE_STRING, &soundKey);
        dbus_message_iter_open_container(&hint, DBUS_TYPE_VARIANT, "b", &value);
        dbus_message_iter_append_basic(&value, DBUS_TYPE_BOOLEAN, &suppress);
        dbus_message_iter_close_container(&hint, &value);
        dbus_message_iter_close_container(&hints, &hint);
    }
    dbus_message_iter_close_container(&arguments, &hints);

    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_INT32, &expires);
    return message;
}

LinuxNotifications::Message LinuxNotifications::messageOf(const Job& job) {
    if (job.work == Work::Close) {
        Message message(dbus_message_new_method_call(kService, kPath, kService, "CloseNotification"), &dbus_message_unref);
        dbus_message_append_args(message.get(), DBUS_TYPE_UINT32, &job.serverId, DBUS_TYPE_INVALID);
        return message;
    }
    if (job.work == Work::Permission) {
        Message message(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "NameHasOwner"), &dbus_message_unref);
        const char* service = kService;
        dbus_message_append_args(message.get(), DBUS_TYPE_STRING, &service, DBUS_TYPE_INVALID);
        return message;
    }
    return notifyMessage(job);
}
