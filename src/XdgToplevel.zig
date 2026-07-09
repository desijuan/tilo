const std = @import("std");
const log = std.log;

const a = std.heap.c_allocator;

const c = @import("c.zig").c;

const Server = @import("Server.zig");
const CursorMode = @import("cursor.zig").CursorMode;

const XdgToplevel = @This();

link: c.wl_list,

wlr_xdg_toplevel: [*c]c.wlr_xdg_toplevel,
wlr_scene_tree: [*c]c.wlr_scene_tree,

l_map: c.wl_listener,
l_unmap: c.wl_listener,
l_commit: c.wl_listener,
l_destroy: c.wl_listener,
l_request_move: c.wl_listener,
l_request_resize: c.wl_listener,
l_request_maximize: c.wl_listener,
l_request_fullscreen: c.wl_listener,

pub fn new(wlr_xdg_toplevel: [*c]c.wlr_xdg_toplevel) error{OutOfMemory}!*XdgToplevel {
    const tl: *XdgToplevel = try a.create(XdgToplevel);
    errdefer a.destroy(tl);

    tl.wlr_xdg_toplevel = wlr_xdg_toplevel;

    tl.wlr_scene_tree = c.wlr_scene_xdg_surface_create(&Server.wlr_scene.*.tree, wlr_xdg_toplevel.*.base);
    tl.wlr_scene_tree.*.node.data = tl;

    wlr_xdg_toplevel.*.base.*.data = tl.wlr_scene_tree;

    tl.l_map.notify = map;
    c.wl_signal_add(&wlr_xdg_toplevel.*.base.*.surface.*.events.map, &tl.l_map);
    tl.l_unmap.notify = unmap;
    c.wl_signal_add(&wlr_xdg_toplevel.*.base.*.surface.*.events.unmap, &tl.l_unmap);
    tl.l_commit.notify = commit;
    c.wl_signal_add(&wlr_xdg_toplevel.*.base.*.surface.*.events.commit, &tl.l_commit);

    tl.l_destroy.notify = destroy;
    c.wl_signal_add(&wlr_xdg_toplevel.*.events.destroy, &tl.l_destroy);

    tl.l_request_move.notify = request_move;
    c.wl_signal_add(&wlr_xdg_toplevel.*.events.request_move, &tl.l_request_move);
    tl.l_request_resize.notify = request_resize;
    c.wl_signal_add(&wlr_xdg_toplevel.*.events.request_resize, &tl.l_request_resize);
    tl.l_request_maximize.notify = request_maximize;
    c.wl_signal_add(&wlr_xdg_toplevel.*.events.request_maximize, &tl.l_request_maximize);
    tl.l_request_fullscreen.notify = request_fullscreen;
    c.wl_signal_add(&wlr_xdg_toplevel.*.events.request_fullscreen, &tl.l_request_fullscreen);

    return tl;
}

// Called when the surface is mapped, or ready to display on-screen.
fn map(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_map", @as(*c.wl_listener, @ptrCast(listener)));
    tl.focus();
}

// Called when the surface is unmapped, and should no longer be shown.
fn unmap(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_unmap", @as(*c.wl_listener, @ptrCast(listener)));
    // Reset the cursor mode if the grabbed toplevel was unmapped.
    if (tl == Server.grabbed_toplevel) Server.resetCursorMode();
}

// Called when a new surface state is committed.
fn commit(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_commit", @as(*c.wl_listener, @ptrCast(listener)));
    // When an xdg_surface performs an initial commit, the compositor must
    // reply with a configure so the client can map the surface. tinywl
    // configures the xdg_toplevel with 0,0 size to let the client pick the
    // dimensions itself.
    if (tl.wlr_xdg_toplevel.*.base.*.initial_commit)
        _ = c.wlr_xdg_toplevel_set_size(tl.wlr_xdg_toplevel, 0, 0);
}

// Called when the xdg_toplevel is destroyed.
fn destroy(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_destroy", @as(*c.wl_listener, @ptrCast(listener)));

    c.wl_list_remove(&tl.l_map.link);
    c.wl_list_remove(&tl.l_unmap.link);
    c.wl_list_remove(&tl.l_commit.link);
    c.wl_list_remove(&tl.l_destroy.link);
    c.wl_list_remove(&tl.l_request_move.link);
    c.wl_list_remove(&tl.l_request_resize.link);
    c.wl_list_remove(&tl.l_request_maximize.link);
    c.wl_list_remove(&tl.l_request_fullscreen.link);

    c.wl_list_remove(&tl.link);

    a.destroy(tl);
}

// This event is raised when a client would like to begin an interactive move, typically because
// the user clicked on their client-side decorations. Note that a more sophisticated compositor
// should check the provided serial against a list of button press serials sent to this client,
// to prevent the client from requesting this whenever they want.
fn request_move(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_request_move", @as(*c.wl_listener, @ptrCast(listener)));
    tl.beginInteractive(.move, 0);
}

// This event is raised when a client would like to begin an interactive resize, typically
// because the user clicked on their client-side decorations. Note that a more sophisticated
// compositor should check the provided serial against a list of button press serials sent to
// this client, to prevent the client from requesting this whenever they want.
fn request_resize(listener: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_request_resize", @as(*c.wl_listener, @ptrCast(listener)));
    const event: [*c]c.wlr_xdg_toplevel_resize_event = @ptrCast(@alignCast(data));
    tl.beginInteractive(.resize, event.*.edges);
}

// This event is raised when a client would like to maximize itself, typically because the
// user clicked on the maximize button on client-side decorations. tinywl doesn't support
// maximization, but to conform to xdg-shell protocol we still must send a configure.
// wlr_xdg_surface_schedule_configure() is used to send an empty reply. However, if the
// request was sent before an initial commit, we don't do anything and let the client
// finish the initial surface setup.
fn request_maximize(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_request_maximize", @as(*c.wl_listener, @ptrCast(listener)));
    if (tl.wlr_xdg_toplevel.*.base.*.initialized)
        _ = c.wlr_xdg_surface_schedule_configure(tl.wlr_xdg_toplevel.*.base);
}

fn request_fullscreen(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const tl: *XdgToplevel = @fieldParentPtr("l_request_fullscreen", @as(*c.wl_listener, @ptrCast(listener)));
    // Just as with request_maximize, we must send a configure here.
    if (tl.wlr_xdg_toplevel.*.base.*.initialized)
        _ = c.wlr_xdg_surface_schedule_configure(tl.wlr_xdg_toplevel.*.base);
}

// Note: this function only deals with keyboard focus.
pub fn focus(tl: *XdgToplevel) void {
    const surface: [*c]c.wlr_surface = tl.wlr_xdg_toplevel.*.base.*.surface;
    const seat: [*c]c.wlr_seat = Server.wlr_seat;

    prev_sf: {
        const prev_surface: [*c]c.wlr_surface = seat.*.keyboard_state.focused_surface;

        // Don't re-focus an already focused surface.
        if (prev_surface == surface) return;

        // Deactivate the previously focused surface. This lets the client know it no longer
        // has focus and the client will repaint accordingly, e.g. stop displaying a caret.
        if (null == prev_surface) break :prev_sf;
        const prev_toplevel: [*c]c.wlr_xdg_toplevel = c.wlr_xdg_toplevel_try_from_wlr_surface(prev_surface);
        if (null == prev_toplevel) break :prev_sf;
        _ = c.wlr_xdg_toplevel_set_activated(prev_toplevel, false);
    }

    // Move the toplevel to the front.
    c.wlr_scene_node_raise_to_top(&tl.wlr_scene_tree.*.node);

    // Activate the new surface.
    _ = c.wlr_xdg_toplevel_set_activated(tl.wlr_xdg_toplevel, true);

    // Tell the seat to have the keyboard enter this surface. wlroots will keep
    // track of this and automatically send key events to the appropriate
    // clients without additional work on your part.
    //
    // zig fmt: off
    const keyboard: [*c]c.wlr_keyboard = c.wlr_seat_get_keyboard(seat);
    if (null != keyboard) c.wlr_seat_keyboard_notify_enter(seat, surface,
        &keyboard.*.keycodes[0], keyboard.*.num_keycodes, &keyboard.*.modifiers,
    ); // zig fmt: on
}

// This function sets up an interactive move or resize operation, where the compositor stops
// propagating pointer events to clients and instead consumes them itself to move or resize windows.
pub fn beginInteractive(tl: *XdgToplevel, mode: CursorMode, edges: u32) void {
    Server.grabbed_toplevel = tl;
    Server.cursor_mode = mode;

    switch (mode) {
        .move => {
            Server.grab_x = Server.wlr_cursor.*.x - tl.wlr_scene_tree.*.node.x;
            Server.grab_y = Server.wlr_cursor.*.y - tl.wlr_scene_tree.*.node.y;
        },

        else => {
            const geo_box: *c.wlr_box = &tl.wlr_xdg_toplevel.*.base.*.geometry;

            const border_x: f64 = (tl.wlr_scene_tree.*.node.x + geo_box.x) +
                if (0 != edges & c.WLR_EDGE_RIGHT) geo_box.width else 0;
            const border_y: f64 = (tl.wlr_scene_tree.*.node.y + geo_box.y) +
                if (0 != edges & c.WLR_EDGE_BOTTOM) geo_box.height else 0;

            Server.grab_x = Server.wlr_cursor.*.x - border_x;
            Server.grab_y = Server.wlr_cursor.*.y - border_y;

            Server.grab_geobox = geo_box.*;
            Server.grab_geobox.x += tl.wlr_scene_tree.*.node.x;
            Server.grab_geobox.y += tl.wlr_scene_tree.*.node.y;

            Server.resize_edges = edges;
        },
    }
}

// This returns the topmost node in the scene at the given layout coords.
// We only care about surface nodes as we are specifically looking for a
// surface in the surface tree of a tinywl_toplevel.
pub fn desktopToplevelAt(lx: f64, ly: f64, surface: *[*c]c.wlr_surface, sx: *f64, sy: *f64) ?*XdgToplevel {
    const node: [*c]c.wlr_scene_node = c.wlr_scene_node_at(&Server.wlr_scene.*.tree.node, lx, ly, sx, sy);
    if (null == node or c.WLR_SCENE_NODE_BUFFER != node.*.type) return null;

    const scene_buffer: [*c]c.wlr_scene_buffer = c.wlr_scene_buffer_from_node(node);
    const scene_surface = c.wlr_scene_surface_try_from_buffer(scene_buffer);
    if (null == scene_surface) return null;

    surface.* = scene_surface.*.surface;

    // Find the node corresponding to the tinywl_toplevel at the root of this
    // surface tree, it is the only one for which we set the data field.
    var tree: [*c]c.wlr_scene_tree = node.*.parent;
    while (null != tree and null == tree.*.node.data) tree = tree.*.node.parent;

    return @as(*XdgToplevel, @ptrCast(@alignCast(tree.*.node.data)));
}
