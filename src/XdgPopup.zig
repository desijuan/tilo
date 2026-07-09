const std = @import("std");
const log = std.log;

const a = std.heap.c_allocator;

const c = @import("c.zig").c;

// const Server = @import("Server.zig");

const XdgPopup = @This();

link: c.wl_list,

wlr_xdg_popup: [*c]c.wlr_xdg_popup,

l_commit: c.wl_listener,
l_destroy: c.wl_listener,

pub fn new(wlr_xdg_popup: [*c]c.wlr_xdg_popup) error{OutOfMemory}!*XdgPopup {
    // We must add xdg popups to the scene graph so they get rendered. The wlroots scene
    // graph provides a helper for this, but to use it we must provide the proper parent
    // scene node of the xdg popup. To enable this, we always set the user data field of
    // xdg_surfaces to the corresponding scene node.
    const parent: [*c]c.wlr_xdg_surface = c.wlr_xdg_surface_try_from_wlr_surface(wlr_xdg_popup.*.parent);
    if (null == parent) @panic("wlr_xdg_surface_try_from_wlr_surface returned null pointer");

    const parent_tree: *c.wlr_scene_tree = @ptrCast(@alignCast(parent.*.data));
    wlr_xdg_popup.*.base.*.data = c.wlr_scene_xdg_surface_create(parent_tree, wlr_xdg_popup.*.base);

    const pu: *XdgPopup = try a.create(XdgPopup);
    errdefer a.destroy(pu);

    pu.wlr_xdg_popup = wlr_xdg_popup;

    pu.l_commit.notify = commit;
    c.wl_signal_add(&wlr_xdg_popup.*.base.*.surface.*.events.commit, &pu.l_commit);
    pu.l_destroy.notify = destroy;
    c.wl_signal_add(&wlr_xdg_popup.*.events.destroy, &pu.l_destroy);

    return pu;
}

// Called when a new surface state is committed.
fn commit(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const pu: *XdgPopup = @fieldParentPtr("l_commit", @as(*c.wl_listener, @ptrCast(listener)));
    if (!pu.wlr_xdg_popup.*.base.*.initial_commit) return;
    // When an xdg_surface performs an initial commit, the compositor must reply with
    // a configure so the client can map the surface. tinywl sends an empty configure.
    // A more sophisticated compositor might change an xdg_popup's geometry to ensure
    // it's not positioned off-screen, for example.
    _ = c.wlr_xdg_surface_schedule_configure(pu.wlr_xdg_popup.*.base);
}

// Called when the xdg_popup is destroyed.
fn destroy(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const pu: *XdgPopup = @fieldParentPtr("l_commit", @as(*c.wl_listener, @ptrCast(listener)));

    c.wl_list_remove(&pu.l_commit.link);
    c.wl_list_remove(&pu.l_destroy.link);

    a.destroy(pu);
}
