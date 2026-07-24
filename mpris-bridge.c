#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <json-c/json.h>
#include <systemd/sd-bus.h>

#define BUS_NAME "org.mpris.MediaPlayer2.dms_lastfm_remote"
#define OBJECT_PATH "/org/mpris/MediaPlayer2"
#define ROOT_IFACE "org.mpris.MediaPlayer2"
#define PLAYER_IFACE "org.mpris.MediaPlayer2.Player"

typedef struct {
    sd_bus *bus;
    bool name_owned;
    char *artist;
    char *title;
    char *album;
    char *art_url;
    char *track_url;
    char *playback_status;
} Bridge;

static void replace_string(char **target, const char *value) {
    char *copy = strdup(value ? value : "");
    if (!copy)
        return;
    free(*target);
    *target = copy;
}

static int get_string(sd_bus *bus, const char *path, const char *interface,
                      const char *property, sd_bus_message *reply,
                      void *userdata, sd_bus_error *error) {
    (void)bus; (void)path; (void)interface; (void)userdata; (void)error;
    const char *value = "";
    if (strcmp(property, "Identity") == 0)
        value = "DMS Last.fm Remote";
    else if (strcmp(property, "DesktopEntry") == 0)
        value = "";
    else if (strcmp(property, "PlaybackStatus") == 0)
        value = ((Bridge *)userdata)->playback_status;
    else if (strcmp(property, "LoopStatus") == 0)
        value = "None";
    return sd_bus_message_append(reply, "s", value);
}

static int get_bool(sd_bus *bus, const char *path, const char *interface,
                    const char *property, sd_bus_message *reply,
                    void *userdata, sd_bus_error *error) {
    (void)bus; (void)path; (void)interface; (void)property;
    (void)userdata; (void)error;
    return sd_bus_message_append(reply, "b", 0);
}

static int get_double(sd_bus *bus, const char *path, const char *interface,
                      const char *property, sd_bus_message *reply,
                      void *userdata, sd_bus_error *error) {
    (void)bus; (void)path; (void)interface; (void)userdata; (void)error;
    double value = strcmp(property, "Volume") == 0 ? 0.0 : 1.0;
    return sd_bus_message_append(reply, "d", value);
}

static int get_position(sd_bus *bus, const char *path, const char *interface,
                        const char *property, sd_bus_message *reply,
                        void *userdata, sd_bus_error *error) {
    (void)bus; (void)path; (void)interface; (void)property;
    (void)userdata; (void)error;
    return sd_bus_message_append(reply, "x", (int64_t)0);
}

static int get_empty_strv(sd_bus *bus, const char *path, const char *interface,
                          const char *property, sd_bus_message *reply,
                          void *userdata, sd_bus_error *error) {
    (void)bus; (void)path; (void)interface; (void)property;
    (void)userdata; (void)error;
    return sd_bus_message_append_strv(reply, NULL);
}

static int append_variant_string(sd_bus_message *reply, const char *key,
                                 const char *value) {
    int r = sd_bus_message_open_container(reply, 'e', "sv");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "s", key);
    if (r < 0) return r;
    r = sd_bus_message_open_container(reply, 'v', "s");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "s", value ? value : "");
    if (r < 0) return r;
    r = sd_bus_message_close_container(reply);
    if (r < 0) return r;
    return sd_bus_message_close_container(reply);
}

static int append_variant_object_path(sd_bus_message *reply, const char *key,
                                      const char *value) {
    int r = sd_bus_message_open_container(reply, 'e', "sv");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "s", key);
    if (r < 0) return r;
    r = sd_bus_message_open_container(reply, 'v', "o");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "o", value);
    if (r < 0) return r;
    r = sd_bus_message_close_container(reply);
    if (r < 0) return r;
    return sd_bus_message_close_container(reply);
}

static int append_variant_strv(sd_bus_message *reply, const char *key,
                               const char *value) {
    int r = sd_bus_message_open_container(reply, 'e', "sv");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "s", key);
    if (r < 0) return r;
    r = sd_bus_message_open_container(reply, 'v', "as");
    if (r < 0) return r;
    r = sd_bus_message_open_container(reply, 'a', "s");
    if (r < 0) return r;
    r = sd_bus_message_append(reply, "s", value ? value : "");
    if (r < 0) return r;
    r = sd_bus_message_close_container(reply);
    if (r < 0) return r;
    r = sd_bus_message_close_container(reply);
    if (r < 0) return r;
    return sd_bus_message_close_container(reply);
}

static int get_metadata(sd_bus *bus, const char *path, const char *interface,
                        const char *property, sd_bus_message *reply,
                        void *userdata, sd_bus_error *error) {
    (void)bus; (void)path; (void)interface; (void)property; (void)error;
    Bridge *bridge = userdata;
    int r = sd_bus_message_open_container(reply, 'a', "{sv}");
    if (r < 0) return r;
    r = append_variant_object_path(reply, "mpris:trackid",
                                   "/org/mpris/MediaPlayer2/track/remote");
    if (r < 0) return r;
    r = append_variant_string(reply, "xesam:title", bridge->title);
    if (r < 0) return r;
    r = append_variant_strv(reply, "xesam:artist", bridge->artist);
    if (r < 0) return r;
    if (bridge->album && bridge->album[0]) {
        r = append_variant_string(reply, "xesam:album", bridge->album);
        if (r < 0) return r;
    }
    if (bridge->art_url && bridge->art_url[0]) {
        r = append_variant_string(reply, "mpris:artUrl", bridge->art_url);
        if (r < 0) return r;
    }
    if (bridge->track_url && bridge->track_url[0]) {
        r = append_variant_string(reply, "xesam:url", bridge->track_url);
        if (r < 0) return r;
    }
    return sd_bus_message_close_container(reply);
}

static int no_op(sd_bus_message *message, void *userdata, sd_bus_error *error) {
    (void)userdata; (void)error;
    return sd_bus_reply_method_return(message, "");
}

static const sd_bus_vtable root_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Raise", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Quit", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("CanQuit", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Fullscreen", "b", get_bool, 0, 0),
    SD_BUS_PROPERTY("CanSetFullscreen", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanRaise", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("HasTrackList", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("Identity", "s", get_string, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("DesktopEntry", "s", get_string, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("SupportedUriSchemes", "as", get_empty_strv, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("SupportedMimeTypes", "as", get_empty_strv, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static const sd_bus_vtable player_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Next", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Previous", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Pause", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("PlayPause", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Stop", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Play", "", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Seek", "x", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SetPosition", "ox", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("OpenUri", "s", "", no_op, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("PlaybackStatus", "s", get_string, 0, SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
    SD_BUS_PROPERTY("LoopStatus", "s", get_string, 0, 0),
    SD_BUS_PROPERTY("Rate", "d", get_double, 0, 0),
    SD_BUS_PROPERTY("Shuffle", "b", get_bool, 0, 0),
    SD_BUS_PROPERTY("Metadata", "a{sv}", get_metadata, 0, SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
    SD_BUS_PROPERTY("Volume", "d", get_double, 0, 0),
    SD_BUS_PROPERTY("Position", "x", get_position, 0, 0),
    SD_BUS_PROPERTY("MinimumRate", "d", get_double, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("MaximumRate", "d", get_double, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanGoNext", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanGoPrevious", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanPlay", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanPause", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanSeek", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("CanControl", "b", get_bool, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static const char *json_string(struct json_object *object, const char *key) {
    struct json_object *value = NULL;
    if (!json_object_object_get_ex(object, key, &value) ||
        !json_object_is_type(value, json_type_string))
        return "";
    return json_object_get_string(value);
}

static void release_name(Bridge *bridge) {
    if (!bridge->name_owned)
        return;
    sd_bus_release_name(bridge->bus, BUS_NAME);
    bridge->name_owned = false;
}

static int acquire_name(Bridge *bridge) {
    if (bridge->name_owned)
        return 0;
    int r = sd_bus_request_name(bridge->bus, BUS_NAME, 0);
    if (r >= 0)
        bridge->name_owned = true;
    return r;
}

static void handle_line(Bridge *bridge, const char *line) {
    struct json_object *object = json_tokener_parse(line);
    if (!object)
        return;
    const char *command = json_string(object, "command");
    if (strcmp(command, "clear") == 0) {
        release_name(bridge);
    } else if (strcmp(command, "set") == 0) {
        replace_string(&bridge->artist, json_string(object, "artist"));
        replace_string(&bridge->title, json_string(object, "title"));
        replace_string(&bridge->album, json_string(object, "album"));
        replace_string(&bridge->art_url, json_string(object, "artUrl"));
        replace_string(&bridge->track_url, json_string(object, "trackUrl"));
        replace_string(&bridge->playback_status, json_string(object, "playbackStatus"));
        if (!bridge->playback_status[0])
            replace_string(&bridge->playback_status, "Playing");
        if (bridge->title[0] && bridge->artist[0] && acquire_name(bridge) >= 0) {
            sd_bus_emit_properties_changed(bridge->bus, OBJECT_PATH, PLAYER_IFACE,
                                           "PlaybackStatus", "Metadata", NULL);
        }
    }
    json_object_put(object);
}

int main(void) {
    Bridge bridge = {0};
    bridge.artist = strdup("");
    bridge.title = strdup("");
    bridge.album = strdup("");
    bridge.art_url = strdup("");
    bridge.track_url = strdup("");
    bridge.playback_status = strdup("Playing");

    int r = sd_bus_open_user(&bridge.bus);
    if (r < 0) {
        fprintf(stderr, "Failed to connect to user bus: %s\n", strerror(-r));
        return 1;
    }
    r = sd_bus_add_object_vtable(bridge.bus, NULL, OBJECT_PATH, ROOT_IFACE,
                                 root_vtable, &bridge);
    if (r < 0) goto finish;
    r = sd_bus_add_object_vtable(bridge.bus, NULL, OBJECT_PATH, PLAYER_IFACE,
                                 player_vtable, &bridge);
    if (r < 0) goto finish;

    char input[65536];
    size_t used = 0;
    for (;;) {
        while ((r = sd_bus_process(bridge.bus, NULL)) > 0) {}
        if (r < 0) break;

        struct pollfd fds[2] = {
            { .fd = STDIN_FILENO, .events = POLLIN },
            { .fd = sd_bus_get_fd(bridge.bus), .events = sd_bus_get_events(bridge.bus) },
        };
        r = poll(fds, 2, -1);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (fds[0].revents & (POLLIN | POLLHUP)) {
            ssize_t count = read(STDIN_FILENO, input + used, sizeof(input) - used - 1);
            if (count <= 0) break;
            used += (size_t)count;
            input[used] = '\0';
            char *start = input;
            char *newline = NULL;
            while ((newline = strchr(start, '\n')) != NULL) {
                *newline = '\0';
                handle_line(&bridge, start);
                start = newline + 1;
            }
            used = strlen(start);
            memmove(input, start, used);
            if (used == sizeof(input) - 1)
                used = 0;
        }
    }

finish:
    release_name(&bridge);
    sd_bus_flush_close_unref(bridge.bus);
    free(bridge.artist);
    free(bridge.title);
    free(bridge.album);
    free(bridge.art_url);
    free(bridge.track_url);
    free(bridge.playback_status);
    return r < 0 ? 1 : 0;
}
