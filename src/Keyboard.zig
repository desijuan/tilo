const std = @import("std");
const log = std.log;
const a = std.heap.c_allocator;

const c = @import("c.zig").c;

const Server = @import("Server.zig");

const foot: [2][*c]u8 = .{ @constCast("foot"), null };

const Keyboard = @This();

link: c.wl_list,

wlr_keyboard: [*c]c.wlr_keyboard,

l_modifiers: c.wl_listener,
l_key: c.wl_listener,
l_destroy: c.wl_listener,

pub fn new(device: [*c]c.wlr_input_device) error{OutOfMemory}!*Keyboard {
    const wlr_keyboard = c.wlr_keyboard_from_input_device(device);

    const kb: *Keyboard = try a.create(Keyboard);
    errdefer a.destroy(kb);

    kb.wlr_keyboard = wlr_keyboard;

    {
        // We need to prepare an XKB keymap and assign it to the keyboard.
        // This assumes the defaults (e.g. layout = "us").
        const context: ?*c.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
        defer c.xkb_context_unref(context);
        const keymap: ?*c.xkb_keymap = c.xkb_keymap_new_from_names(context, null, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
        defer c.xkb_keymap_unref(keymap);
        _ = c.wlr_keyboard_set_keymap(wlr_keyboard, keymap);
    }
    c.wlr_keyboard_set_repeat_info(wlr_keyboard, 25, 600);

    // Here we set up listeners for keyboard events.
    kb.l_modifiers.notify = modifiers;
    c.wl_signal_add(&wlr_keyboard.*.events.modifiers, &kb.l_modifiers);
    kb.l_key.notify = key;
    c.wl_signal_add(&wlr_keyboard.*.events.key, &kb.l_key);
    kb.l_destroy.notify = destroy;
    c.wl_signal_add(&device.*.events.destroy, &kb.l_destroy);

    c.wlr_seat_set_keyboard(Server.wlr_seat, kb.wlr_keyboard);

    // And add the keyboard to our list of keyboards.
    c.wl_list_insert(&Server.keyboards, &kb.link);

    return kb;
}

// This event is raised when a modifier key, such as shift or alt, is
// pressed. We simply communicate this to the client.
fn modifiers(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const kb: *Keyboard = @fieldParentPtr("l_modifiers", @as(*c.wl_listener, @ptrCast(listener)));
    c.wlr_seat_set_keyboard(Server.wlr_seat, kb.wlr_keyboard);
    c.wlr_seat_keyboard_notify_modifiers(Server.wlr_seat, &kb.wlr_keyboard.*.modifiers);
}

// This event is raised when a key is pressed or released.
fn key(listener: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const kb: *Keyboard = @fieldParentPtr("l_key", @as(*c.wl_listener, @ptrCast(listener)));
    const event: [*c]c.wlr_keyboard_key_event = @ptrCast(@alignCast(data));

    const mods: c_int = @intCast(c.wlr_keyboard_get_modifiers(kb.wlr_keyboard));

    // Translate libinput keycode -> xkbcommon.
    const keycode: u32 = event.*.keycode + 8;
    // Get a list of keysyms based on the keymap for this keyboard.
    var syms: [*c]const c.xkb_keysym_t = undefined;
    const nsyms: usize = @intCast(c.xkb_state_key_get_syms(kb.*.wlr_keyboard.*.xkb_state, keycode, &syms));

    switch (event.*.state) {
        c.WL_KEYBOARD_KEY_STATE_RELEASED => {},

        // If a button was pressed, we attempt to process it as a compositor keybinding.
        c.WL_KEYBOARD_KEY_STATE_PRESSED => for (0..nsyms) |i| if (handleKeybinding(mods, syms[i])) return,

        c.WL_KEYBOARD_KEY_STATE_REPEATED => {},

        else => unreachable,
    }

    kb.notifyKeyEvent(event);
}

fn destroy(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const kb: *Keyboard = @fieldParentPtr("l_destroy", @as(*c.wl_listener, @ptrCast(listener)));

    c.wl_list_remove(&kb.l_modifiers.link);
    c.wl_list_remove(&kb.l_key.link);
    c.wl_list_remove(&kb.l_destroy.link);

    c.wl_list_remove(&kb.link);

    a.destroy(kb);
}

fn notifyKeyEvent(kb: Keyboard, event: [*c]c.wlr_keyboard_key_event) void {
    c.wlr_seat_set_keyboard(Server.wlr_seat, kb.wlr_keyboard);
    c.wlr_seat_keyboard_notify_key(Server.wlr_seat, event.*.time_msec, event.*.keycode, event.*.state);
}

// Here we handle compositor keybindings. This is when the compositor is processing
// keys, rather than passing them on to the client for its own processing.
fn handleKeybinding(mods: c_int, sym: c.xkb_keysym_t) bool {
    return if (0 != (c.WLR_MODIFIER_ALT & mods)) switch (sym) {
        c.XKB_KEY_Escape => blk: {
            Server.terminate();
            break :blk true;
        },

        c.XKB_KEY_a => blk: {
            Server.spawn(&foot);
            break :blk true;
        },

        else => false,
    } else false;
}
