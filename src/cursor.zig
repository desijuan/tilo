const std = @import("std");

const c = @import("c.zig").c;

const Server = @import("Server.zig");
const XdgToplevel = @import("XdgToplevel.zig");

pub const CursorMode = enum {
    passthrough,
    move,
    resize,

    pub fn processCursorMotion(self: CursorMode, time: u32) void {
        return switch (self) {
            .passthrough => processPassthrough(time),
            .move => processMove(),
            .resize => processResize(),
        };
    }

    // Find the toplevel under the pointer and send the event along.
    fn processPassthrough(time: u32) void {
        var sx: f64 = undefined;
        var sy: f64 = undefined;
        var surface: [*c]c.wlr_surface = null;
        const toplevel: ?*XdgToplevel =
            .desktopToplevelAt(Server.wlr_cursor.*.x, Server.wlr_cursor.*.y, &surface, &sx, &sy);

        // If there's no toplevel under the cursor, set the cursor image to a default.
        // This is what makes the cursor image appear when you move it around the screen,
        // not over any toplevels.
        if (null == toplevel)
            c.wlr_cursor_set_xcursor(Server.wlr_cursor, Server.wlr_cursor_manager, "default");

        // Clear pointer focus so future button events and such are not sent to
        // the last client to have the cursor over it.
        if (null == surface) {
            c.wlr_seat_pointer_clear_focus(Server.wlr_seat);
            return;
        }

        // Send pointer enter and motion events.
        //
        // The enter event gives the surface "pointer focus", which is distinct
        // from keyboard focus. You get pointer focus by moving the pointer over
        // a window.
        //
        // Note that wlroots will avoid sending duplicate enter/motion events if
        // the surface has already has pointer focus or if the client is already
        // aware of the coordinates passed.
        c.wlr_seat_pointer_notify_enter(Server.wlr_seat, surface, sx, sy);
        c.wlr_seat_pointer_notify_motion(Server.wlr_seat, time, sx, sy);
    }

    // Move the grabbed toplevel to the new position.
    fn processMove() void {
        c.wlr_scene_node_set_position(
            &Server.grabbed_toplevel.?.wlr_scene_tree.*.node,
            @round(Server.wlr_cursor.*.x - Server.grab_x),
            @round(Server.wlr_cursor.*.y - Server.grab_y),
        );
    }

    // Resizing the grabbed toplevel can be a little bit complicated, because we
    // could be resizing from any corner or edge. This not only resizes the
    // toplevel on one or two axes, but can also move the toplevel if you resize
    // from the top or left edges (or top-left corner).
    //
    // Note that some shortcuts are taken here. In a more fleshed-out
    // compositor, you'd wait for the client to prepare a buffer at the new
    // size, then commit any movement that was prepared.
    fn processResize() void {
        const tl: *XdgToplevel = Server.grabbed_toplevel.?;
        const border_x: f64 = Server.wlr_cursor.*.x - Server.grab_x;
        const border_y: f64 = Server.wlr_cursor.*.y - Server.grab_y;

        var new_left: c_int = Server.grab_geobox.x;
        var new_right: c_int = Server.grab_geobox.x - Server.grab_geobox.width;
        var new_top: c_int = Server.grab_geobox.y;
        var new_bottom: c_int = Server.grab_geobox.y - Server.grab_geobox.height;

        if (0 != (c.WLR_EDGE_TOP & @as(c_int, @intCast(Server.resize_edges)))) {
            new_top = @round(border_y);
            if (new_top >= new_bottom) new_top = new_bottom - 1;
        } else if (0 != (c.WLR_EDGE_BOTTOM & @as(c_int, @intCast(Server.resize_edges)))) {
            new_bottom = @round(border_y);
            if (new_bottom <= new_top) new_bottom = new_top + 1;
        }

        if (0 != (c.WLR_EDGE_LEFT & @as(c_int, @intCast(Server.resize_edges)))) {
            new_left = @round(border_x);
            if (new_left >= new_right) new_left = new_right - 1;
        } else if (0 != (c.WLR_EDGE_RIGHT & @as(c_int, @intCast(Server.resize_edges)))) {
            new_right = @round(border_x);
            if (new_right <= new_left) new_right = new_left + 1;
        }

        const geo_box: *const c.wlr_box = &tl.wlr_xdg_toplevel.*.base.*.geometry;

        c.wlr_scene_node_set_position(
            &tl.wlr_scene_tree.*.node,
            new_left - geo_box.x,
            new_top - geo_box.y,
        );

        const new_width: c_int = new_right - new_left;
        const new_height: c_int = new_bottom - new_top;

        _ = c.wlr_xdg_toplevel_set_size(tl.wlr_xdg_toplevel, new_width, new_height);
    }
};
