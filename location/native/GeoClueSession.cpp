#include "GeoClueSession.hpp"

#include <array>
#include <limits>
#include <utility>

#include "LocationBridge.hpp"

void GeoClueSession::ConnectionClose::operator()(DBusConnection* connection) const {
    dbus_connection_close(connection);
    dbus_connection_unref(connection);
}

void GeoClueSession::MessageRelease::operator()(DBusMessage* message) const {
    dbus_message_unref(message);
}

void GeoClueSession::PendingRelease::operator()(DBusPendingCall* pending) const {
    dbus_pending_call_unref(pending);
}

GeoClueSession::BusError::BusError() {
    dbus_error_init(&value);
}

GeoClueSession::BusError::~BusError() {
    dbus_error_free(&value);
}

bool GeoClueSession::BusError::is(const char* name) const {
    return dbus_error_has_name(&value, name) != 0;
}

std::string GeoClueSession::BusError::describe() const {
    return value.message != nullptr ? value.message : "no reason";
}

GeoClueSession::~GeoClueSession() {
    end();
}

std::optional<std::string_view> GeoClueSession::findMissing() {
    BusError error;
    const Connection bus = connectSystemBus(error);
    if (!bus) {
        return kMissingBus;
    }

    if (dbus_bus_name_has_owner(bus.get(), kService, nullptr)) {
        return std::nullopt;
    }
    const Message listing(dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS, DBUS_INTERFACE_DBUS, "ListActivatableNames"));
    const Message reply = call(bus.get(), listing, nullptr);
    char** names = nullptr;
    int count = 0;
    if (!reply || !dbus_message_get_args(reply.get(), nullptr, DBUS_TYPE_ARRAY, DBUS_TYPE_STRING, &names, &count, DBUS_TYPE_INVALID)) {
        return kMissingService;
    }

    bool activatable = false;
    for (int index = 0; index < count; ++index) {
        activatable = activatable || std::string_view(names[index]) == kService;
    }
    dbus_free_string_array(names);
    if (activatable) {
        return std::nullopt;
    }
    return kMissingService;
}

std::optional<GeoClueSession::Failure> GeoClueSession::begin(const std::string& desktopId, std::uint32_t distance, const std::function<bool()>& isWanted) {
    std::optional<Failure> failure = start(desktopId, distance, isWanted);
    if (failure) {
        client.clear();
        end();
    }
    return failure;
}

void GeoClueSession::end() {
    if (!connection) {
        return;
    }
    if (!client.empty()) {
        const Message stopping = method(client.c_str(), kClientInterface, "Stop");
        const Message stopped = call(connection.get(), stopping, nullptr);
    }
    if (filtering) {
        dbus_connection_remove_filter(connection.get(), &GeoClueSession::filter, this);
    }

    connection.reset();
    client.clear();
    updated.clear();
    delivered.clear();
    place.reset();
    filtering = false;
    revoked = false;
    vanished = false;
}

bool GeoClueSession::isOpen() const {
    return connection != nullptr;
}

bool GeoClueSession::isRevoked() const {
    return revoked;
}

bool GeoClueSession::hasVanished() const {
    return vanished;
}

bool GeoClueSession::setDistance(std::uint32_t distance) {
    const dbus_uint32_t threshold = distance;
    return setProperty(client.c_str(), kClientInterface, "DistanceThreshold", DBUS_TYPE_UINT32, &threshold, nullptr);
}

// A new place goes to the watch and the waiting calls, and the last place answers the calls that came while the client ran. The signal of the first place may repeat the place that the start read already.
std::optional<GeoClueSession::Place> GeoClueSession::takePlace() {
    const bool fresh = !updated.empty() && updated != delivered;
    std::optional<Json> read = fresh ? readPlace(updated) : std::nullopt;
    if (!updated.empty()) {
        delivered = std::move(updated);
        updated.clear();
    }

    if (!fresh) {
        if (!place) {
            return std::nullopt;
        }
        return Place{.value = *place, .updated = false};
    }
    if (!read) {
        return std::nullopt;
    }
    place = std::move(read);
    return Place{.value = *place, .updated = true};
}

bool GeoClueSession::dispatch() {
    return dbus_connection_read_write_dispatch(connection.get(), kDispatchMilliseconds) != 0;
}

GeoClueSession::Connection GeoClueSession::connectSystemBus(BusError& error) {
    Connection bus(dbus_bus_get_private(DBUS_BUS_SYSTEM, &error.value));
    if (bus) {
        dbus_connection_set_exit_on_disconnect(bus.get(), FALSE);
    }
    return bus;
}

GeoClueSession::Message GeoClueSession::method(const char* path, const char* interface, const char* member) {
    return Message(dbus_message_new_method_call(kService, path, interface, member));
}

GeoClueSession::Message GeoClueSession::call(DBusConnection* bus, const Message& message, DBusError* error) {
    return Message(dbus_connection_send_with_reply_and_block(bus, message.get(), kCallMilliseconds, error));
}

double GeoClueSession::now() {
    const std::chrono::duration<double> since = std::chrono::system_clock::now().time_since_epoch();
    return since.count();
}

DBusHandlerResult GeoClueSession::filter(DBusConnection*, DBusMessage* message, void* user) {
    return static_cast<GeoClueSession*>(user)->receive(message);
}

// Keeps the place of each update of the client, and whether the agent took the client away or GeoClue left the bus while it ran.
DBusHandlerResult GeoClueSession::receive(DBusMessage* message) {
    if (dbus_message_is_signal(message, DBUS_INTERFACE_DBUS, "NameOwnerChanged")) {
        const char* name = nullptr;
        const char* previous = nullptr;
        const char* current = nullptr;
        const bool read = dbus_message_get_args(message, nullptr, DBUS_TYPE_STRING, &name, DBUS_TYPE_STRING, &previous, DBUS_TYPE_STRING, &current, DBUS_TYPE_INVALID);
        if (read && std::string_view(name) == kService && current[0] == '\0') {
            vanished = true;
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (!dbus_message_has_path(message, client.c_str())) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

    if (dbus_message_is_signal(message, kClientInterface, "LocationUpdated")) {
        const char* previous = nullptr;
        const char* current = nullptr;
        if (dbus_message_get_args(message, nullptr, DBUS_TYPE_OBJECT_PATH, &previous, DBUS_TYPE_OBJECT_PATH, &current, DBUS_TYPE_INVALID)) {
            updated = current;
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (!dbus_message_is_signal(message, kProperties, "PropertiesChanged")) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }
    DBusMessageIter arguments;
    DBusMessageIter changes;
    if (!dbus_message_iter_init(message, &arguments) || !dbus_message_iter_next(&arguments) || dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_ARRAY) {
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    for (dbus_message_iter_recurse(&arguments, &changes); dbus_message_iter_get_arg_type(&changes) == DBUS_TYPE_DICT_ENTRY; dbus_message_iter_next(&changes)) {
        DBusMessageIter entry;
        DBusMessageIter variant;
        const char* name = nullptr;
        dbus_message_iter_recurse(&changes, &entry);
        dbus_message_iter_get_basic(&entry, &name);
        dbus_message_iter_next(&entry);
        dbus_message_iter_recurse(&entry, &variant);
        if (std::string_view(name) != "Active" || dbus_message_iter_get_arg_type(&variant) != DBUS_TYPE_BOOLEAN) {
            continue;
        }
        dbus_bool_t active = TRUE;
        dbus_message_iter_get_basic(&variant, &active);
        revoked = revoked || !active;
    }
    return DBUS_HANDLER_RESULT_HANDLED;
}

std::optional<GeoClueSession::Failure> GeoClueSession::start(const std::string& desktopId, std::uint32_t distance, const std::function<bool()>& isWanted) {
    BusError error;
    connection = connectSystemBus(error);
    if (!connection) {
        return Failure{.code = "unsupported", .message = std::string(kMissingBus)};
    }

    dbus_uint32_t available = 0;
    if (!getProperty(kManager, kManagerInterface, "AvailableAccuracyLevel", DBUS_TYPE_UINT32, &available, &error.value)) {
        if (error.is(DBUS_ERROR_SERVICE_UNKNOWN) || error.is(DBUS_ERROR_NAME_HAS_NO_OWNER)) {
            return Failure{.code = "unsupported", .message = std::string(kMissingService)};
        }
        return Failure{.code = "locationUnknown", .message = "The location is unknown: GeoClue failed with \"" + error.describe() + "\"."};
    }
    if (available == 0) {
        return Failure{.code = "locationOff", .message = std::string(LocationBridge::kLocationOff)};
    }

    // GeoClue makes the client once the agent of the session of the person registered, which a desktop does as its session starts, so a desktop without an agent gives no app the location.
    Message reply;
    const Waited made = wait(method(kManager, kManagerInterface, "GetClient"), kAgentSeconds, isWanted, reply);
    if (made == Waited::Abandoned) {
        return Failure{.code = "cancelled", .message = std::string(kNoLongerWanted)};
    }
    if (made == Waited::Unanswered) {
        return Failure{.code = "unsupported", .message = std::string(kMissingAgent)};
    }
    const char* path = nullptr;
    if (dbus_set_error_from_message(&error.value, reply.get()) || !dbus_message_get_args(reply.get(), &error.value, DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_INVALID)) {
        const char* code = error.is(DBUS_ERROR_ACCESS_DENIED) ? "denied" : "locationUnknown";
        return Failure{.code = code, .message = "The location is unknown: GeoClue gave the app no client, with \"" + error.describe() + "\"."};
    }
    client = path;
    reply.reset();

    const char* desktop = desktopId.c_str();
    const dbus_uint32_t accuracy = kAccuracyExact;
    const dbus_uint32_t threshold = distance;
    const bool named = setProperty(client.c_str(), kClientInterface, "DesktopId", DBUS_TYPE_STRING, &desktop, &error.value);
    const bool accurate = named && setProperty(client.c_str(), kClientInterface, "RequestedAccuracyLevel", DBUS_TYPE_UINT32, &accuracy, &error.value);
    const bool filtered = accurate && setProperty(client.c_str(), kClientInterface, "DistanceThreshold", DBUS_TYPE_UINT32, &threshold, &error.value);
    if (!filtered) {
        return Failure{.code = "locationUnknown", .message = "The location is unknown: GeoClue refused the settings of the client with \"" + error.describe() + "\"."};
    }

    const std::string signals = std::string("type='signal',sender='") + kService + "',path='" + client + "'";
    const std::string owners = std::string("type='signal',sender='") + DBUS_SERVICE_DBUS + "',interface='" + DBUS_INTERFACE_DBUS + "',member='NameOwnerChanged',arg0='" + kService + "'";
    dbus_bus_add_match(connection.get(), signals.c_str(), &error.value);
    if (!dbus_error_is_set(&error.value)) {
        dbus_bus_add_match(connection.get(), owners.c_str(), &error.value);
    }
    filtering = !dbus_error_is_set(&error.value) && dbus_connection_add_filter(connection.get(), &GeoClueSession::filter, this, nullptr);
    if (!filtering) {
        return Failure{.code = "locationUnknown", .message = "The location is unknown: the bus refused the signals of GeoClue."};
    }

    // The agent of GeoClue may ask the person before the start answers, so the start waits as long as the app wants the location.
    const Waited started = wait(method(client.c_str(), kClientInterface, "Start"), std::chrono::duration<double>::zero(), isWanted, reply);
    if (started == Waited::Abandoned) {
        return Failure{.code = "cancelled", .message = std::string(kNoLongerWanted)};
    }
    if (started == Waited::Unanswered || dbus_set_error_from_message(&error.value, reply.get())) {
        const char* code = error.is(DBUS_ERROR_ACCESS_DENIED) ? "denied" : "locationUnknown";
        return Failure{.code = code, .message = "The location is unknown: GeoClue did not start, with \"" + error.describe() + "\"."};
    }

    // A client that GeoClue already ran for the app holds its location at once.
    const char* known = nullptr;
    if (getProperty(client.c_str(), kClientInterface, "Location", DBUS_TYPE_OBJECT_PATH, &known, nullptr) && std::string_view(known) != "/") {
        updated = known;
    }
    return std::nullopt;
}

// Sends a method call and waits for its reply while the app still wants the location and, with a bound above zero, for at most that long.
GeoClueSession::Waited GeoClueSession::wait(const Message& message, std::chrono::duration<double> bound, const std::function<bool()>& isWanted, Message& reply) {
    DBusPendingCall* sent = nullptr;
    const bool queued = dbus_connection_send_with_reply(connection.get(), message.get(), &sent, DBUS_TIMEOUT_INFINITE);
    const Pending pending(sent);
    if (!queued || !pending) {
        return Waited::Unanswered;
    }

    const auto deadline = std::chrono::steady_clock::now() + std::chrono::duration_cast<std::chrono::steady_clock::duration>(bound);
    while (!dbus_pending_call_get_completed(pending.get())) {
        if (!isWanted() || !dbus_connection_read_write_dispatch(connection.get(), kDispatchMilliseconds)) {
            dbus_pending_call_cancel(pending.get());
            return Waited::Abandoned;
        }
        if (bound.count() > 0 && std::chrono::steady_clock::now() > deadline) {
            dbus_pending_call_cancel(pending.get());
            return Waited::Unanswered;
        }
    }
    reply.reset(dbus_pending_call_steal_reply(pending.get()));
    return Waited::Answered;
}

bool GeoClueSession::setProperty(const char* path, const char* interface, const char* name, int type, const void* value, DBusError* error) {
    const Message message = method(path, kProperties, "Set");
    const std::array<char, 2> signature{static_cast<char>(type), '\0'};
    DBusMessageIter arguments;
    DBusMessageIter variant;
    dbus_message_iter_init_append(message.get(), &arguments);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &interface);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &name);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_VARIANT, signature.data(), &variant);
    dbus_message_iter_append_basic(&variant, type, value);
    dbus_message_iter_close_container(&arguments, &variant);
    return call(connection.get(), message, error) != nullptr;
}

bool GeoClueSession::getProperty(const char* path, const char* interface, const char* name, int type, void* value, DBusError* error) {
    const Message message = method(path, kProperties, "Get");
    dbus_message_append_args(message.get(), DBUS_TYPE_STRING, &interface, DBUS_TYPE_STRING, &name, DBUS_TYPE_INVALID);
    const Message reply = call(connection.get(), message, error);
    if (!reply) {
        return false;
    }

    DBusMessageIter arguments;
    DBusMessageIter variant;
    if (!dbus_message_iter_init(reply.get(), &arguments) || dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_VARIANT) {
        return false;
    }
    dbus_message_iter_recurse(&arguments, &variant);
    if (dbus_message_iter_get_arg_type(&variant) != type) {
        return false;
    }
    dbus_message_iter_get_basic(&variant, value);
    return true;
}

// Reads the location object of an update into a place of the plugin, leaving out what GeoClue marks unknown: an altitude of the lowest double, and a speed or a heading below zero.
std::optional<GeoClueSession::Json> GeoClueSession::readPlace(const std::string& path) {
    const char* interface = kLocationInterface;
    const Message message = method(path.c_str(), kProperties, "GetAll");
    dbus_message_append_args(message.get(), DBUS_TYPE_STRING, &interface, DBUS_TYPE_INVALID);
    const Message reply = call(connection.get(), message, nullptr);
    DBusMessageIter arguments;
    if (!reply || !dbus_message_iter_init(reply.get(), &arguments) || dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_ARRAY) {
        return std::nullopt;
    }

    double latitude = 0;
    double longitude = 0;
    double accuracy = 0;
    double altitude = std::numeric_limits<double>::lowest();
    double speed = -1;
    double heading = -1;
    double timestamp = 0;
    const std::array<std::pair<std::string_view, double*>, 6> fields{{{"Latitude", &latitude}, {"Longitude", &longitude}, {"Accuracy", &accuracy}, {"Altitude", &altitude}, {"Speed", &speed}, {"Heading", &heading}}};
    DBusMessageIter properties;
    for (dbus_message_iter_recurse(&arguments, &properties); dbus_message_iter_get_arg_type(&properties) == DBUS_TYPE_DICT_ENTRY; dbus_message_iter_next(&properties)) {
        DBusMessageIter entry;
        DBusMessageIter variant;
        const char* name = nullptr;
        dbus_message_iter_recurse(&properties, &entry);
        dbus_message_iter_get_basic(&entry, &name);
        dbus_message_iter_next(&entry);
        dbus_message_iter_recurse(&entry, &variant);
        const int type = dbus_message_iter_get_arg_type(&variant);

        if (type == DBUS_TYPE_STRUCT && std::string_view(name) == "Timestamp") {
            DBusMessageIter parts;
            dbus_uint64_t seconds = 0;
            dbus_uint64_t microseconds = 0;
            dbus_message_iter_recurse(&variant, &parts);
            dbus_message_iter_get_basic(&parts, &seconds);
            dbus_message_iter_next(&parts);
            dbus_message_iter_get_basic(&parts, &microseconds);
            timestamp = static_cast<double>(seconds) + static_cast<double>(microseconds) / 1e6;
            continue;
        }
        if (type != DBUS_TYPE_DOUBLE) {
            continue;
        }
        double value = 0;
        dbus_message_iter_get_basic(&variant, &value);
        for (const auto& [field, target] : fields) {
            if (field == name) {
                *target = value;
            }
        }
    }

    Json result = {{"latitude", latitude}, {"longitude", longitude}, {"accuracy", accuracy}, {"timestamp", timestamp > 0 ? timestamp : now()}};
    if (altitude > std::numeric_limits<double>::lowest()) {
        result["altitude"] = altitude;
    }
    if (speed >= 0) {
        result["speed"] = speed;
    }
    if (heading >= 0) {
        result["heading"] = heading;
    }
    return result;
}
