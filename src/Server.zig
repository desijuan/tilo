const std = @import("std");
const log = std.log;
const mem = std.mem;
const posix = std.posix;

const a = std.heap.c_allocator;

const c = @import("c.zig").c;

//  -----------------------
//  ------ Variables ------
//  -----------------------

//
// Socket
//
var socket: [*c]const u8 = undefined;

//
// Display
//
pub var wl_display: *c.wl_display = undefined;
var wl_event_loop: *c.wl_event_loop = undefined;
var wlr_backend: [*c]c.wlr_backend = undefined;
var wlr_renderer: [*c]c.wlr_renderer = undefined;
var wlr_allocator: [*c]c.wlr_allocator = undefined;

//
// Scene
//
pub var wlr_scene: [*c]c.wlr_scene = undefined;
var wlr_scene_layout: *c.wlr_scene_output_layout = undefined;

//
// XDG Shell
//
var wlr_xdg_shell: *c.wlr_xdg_shell = undefined;

//
// XDG Popup
//
var l_new_xdg_popup: c.wl_listener = undefined;
const XdgPopup = @import("XdgPopup.zig");

//
// XDG Toplevel
//
var l_new_xdg_toplevel: c.wl_listener = undefined;
const XdgToplevel = @import("XdgToplevel.zig");
pub var toplevels: c.wl_list = undefined;

//
// Cursor
//
pub var wlr_cursor: [*c]c.wlr_cursor = undefined;
pub var wlr_cursor_manager: [*c]c.wlr_xcursor_manager = undefined;
var l_cursor_motion: c.wl_listener = undefined;
var l_cursor_motion_absolute: c.wl_listener = undefined;
var l_cursor_button: c.wl_listener = undefined;
var l_cursor_axis: c.wl_listener = undefined;
var l_cursor_frame: c.wl_listener = undefined;

//
// Seat
//
pub var wlr_seat: [*c]c.wlr_seat = undefined;
var l_new_input: c.wl_listener = undefined;
var l_request_cursor: c.wl_listener = undefined;
var l_pointer_focus_change: c.wl_listener = undefined;
var l_request_set_selection: c.wl_listener = undefined;

//
// Keyboards
//
const Keyboard = @import("Keyboard.zig");
pub var keyboards: c.wl_list = undefined;

//
// Cursor Mode, Move & Resize
//
const CursorMode = @import("cursor.zig").CursorMode;
pub var cursor_mode: CursorMode = .passthrough;
pub var grabbed_toplevel: ?*XdgToplevel = null;
pub var grab_x: f64 = undefined;
pub var grab_y: f64 = undefined;
pub var grab_geobox: c.wlr_box = undefined;
pub var resize_edges: u32 = undefined;

//
// Outputs
//
var wlr_output_layout: [*c]c.wlr_output_layout = undefined;
var l_new_output: c.wl_listener = undefined;
const Output = @import("Output.zig");
var outputs: c.wl_list = undefined;

//  ---------------------
//  ------ Methods ------
//  ---------------------

pub const InitError = error{
    WlDisplayCreateFailed,
    WlDisplayGetEventLoopFailed,
    WlrBackendAutocreateFailed,
    WlrRendererAutocreateFailed,
};

pub fn init() InitError!void {
    log.info("Initializing display", .{});

    wl_display = c.wl_display_create() orelse {
        log.err("Failed to create wl_display", .{});
        return error.WlDisplayCreateFailed;
    };

    wl_event_loop = c.wl_display_get_event_loop(wl_display) orelse {
        log.err("Failed to get event loop", .{});
        return error.WlDisplayGetEventLoopFailed;
    };

    wlr_backend = c.wlr_backend_autocreate(wl_event_loop, null);
    if (wlr_backend == null) {
        log.err("Failed to create wlr_backend", .{});
        return error.WlrBackendAutocreateFailed;
    }

    wlr_renderer = c.wlr_renderer_autocreate(wlr_backend);
    if (wlr_renderer == null) {
        log.err("Failed to create wlr_renderer", .{});
        return error.WlrRendererAutocreateFailed;
    }

    if (!c.wlr_renderer_init_wl_display(wlr_renderer, wl_display)) {
        return error.WlrRendererInitWlDisplayFailed;
    }

    wlr_allocator = c.wlr_allocator_autocreate(wlr_backend, wlr_renderer);
    if (wlr_allocator == null) {
        log.err("Failed to create wlr_allocator", .{});
        return error.WlrAllocatorAutocreateFailed;
    }

    _ = c.wlr_compositor_create(wl_display, 5, wlr_renderer);
    _ = c.wlr_subcompositor_create(wl_display);
    _ = c.wlr_data_device_manager_create(wl_display);

    wlr_output_layout = c.wlr_output_layout_create(wl_display);

    c.wl_list_init(&outputs);

    l_new_output.notify = new_output;
    c.wl_signal_add(&wlr_backend.*.events.new_output, &l_new_output);

    wlr_scene = c.wlr_scene_create();
    wlr_scene_layout = c.wlr_scene_attach_output_layout(wlr_scene, wlr_output_layout) orelse
        return error.WlrSceneAttachOutputLayoutFailed;

    c.wl_list_init(&toplevels);
    wlr_xdg_shell = c.wlr_xdg_shell_create(wl_display, 3);
    l_new_xdg_toplevel.notify = new_xdg_toplevel;
    c.wl_signal_add(&wlr_xdg_shell.*.events.new_toplevel, &l_new_xdg_toplevel);
    l_new_xdg_popup.notify = new_xdg_popup;
    c.wl_signal_add(&wlr_xdg_shell.*.events.new_popup, &l_new_xdg_popup);

    wlr_cursor = c.wlr_cursor_create();
    c.wlr_cursor_attach_output_layout(wlr_cursor, wlr_output_layout);

    wlr_cursor_manager = c.wlr_xcursor_manager_create(null, 24);

    l_cursor_motion.notify = cursor_motion;
    c.wl_signal_add(&wlr_cursor.*.events.motion, &l_cursor_motion);
    l_cursor_motion_absolute.notify = cursor_motion_absolute;
    c.wl_signal_add(&wlr_cursor.*.events.motion_absolute, &l_cursor_motion_absolute);
    l_cursor_button.notify = cursor_button;
    c.wl_signal_add(&wlr_cursor.*.events.button, &l_cursor_button);
    l_cursor_axis.notify = cursor_axis;
    c.wl_signal_add(&wlr_cursor.*.events.axis, &l_cursor_axis);
    l_cursor_frame.notify = cursor_frame;
    c.wl_signal_add(&wlr_cursor.*.events.frame, &l_cursor_frame);

    c.wl_list_init(&keyboards);
    l_new_input.notify = new_input;
    c.wl_signal_add(&wlr_backend.*.events.new_input, &l_new_input);

    wlr_seat = c.wlr_seat_create(wl_display, "seat0");
    l_request_cursor.notify = request_cursor;
    c.wl_signal_add(&wlr_seat.*.events.request_set_cursor, &l_request_cursor);
    l_pointer_focus_change.notify = pointer_focus_change;
    c.wl_signal_add(&wlr_seat.*.pointer_state.events.focus_change, &l_pointer_focus_change);
    l_request_set_selection.notify = request_set_selection;
    c.wl_signal_add(&wlr_seat.*.events.request_set_selection, &l_request_set_selection);

    socket = c.wl_display_add_socket_auto(wl_display);
    if (null == socket) {
        c.wlr_backend_destroy(wlr_backend);
        return error.WlDisplayAddSocketAutoFailed;
    }

    if (!c.wlr_backend_start(wlr_backend)) {
        c.wl_display_destroy(wl_display);
        c.wlr_backend_destroy(wlr_backend);
        return error.WlrBackendStartFailed;
    }

    if (0 != c.setenv("WAYLAND_DISPLAY", socket, 1))
        return error.SetEnvFailed;
}

pub fn deinit() void {
    log.info("Deinitializing display", .{});

    c.wl_display_destroy_clients(wl_display);

    c.wl_list_remove(&l_new_xdg_toplevel.link);
    c.wl_list_remove(&l_new_xdg_popup.link);

    c.wl_list_remove(&l_cursor_motion.link);
    c.wl_list_remove(&l_cursor_motion_absolute.link);
    c.wl_list_remove(&l_cursor_button.link);
    c.wl_list_remove(&l_cursor_axis.link);
    c.wl_list_remove(&l_cursor_frame.link);

    c.wl_list_remove(&l_new_input.link);
    c.wl_list_remove(&l_request_cursor.link);
    c.wl_list_remove(&l_pointer_focus_change.link);
    c.wl_list_remove(&l_request_set_selection.link);

    c.wl_list_remove(&l_new_output.link);

    c.wlr_scene_node_destroy(&wlr_scene.*.tree.node);
    c.wlr_xcursor_manager_destroy(wlr_cursor_manager);
    c.wlr_cursor_destroy(wlr_cursor);
    c.wlr_allocator_destroy(wlr_allocator);
    c.wlr_renderer_destroy(wlr_renderer);
    c.wlr_backend_destroy(wlr_backend);
    c.wl_display_destroy(wl_display);
}

pub fn run() void {
    log.info("Running Wayland compositor on WAYLAND_DISPLAY={s}", .{socket});
    c.wl_display_run(wl_display);
}

pub fn terminate() void {
    c.wl_display_terminate(wl_display);
}

pub fn resetCursorMode() void {
    // Reset the cursor mode to passthrough.
    cursor_mode = .passthrough;
    grabbed_toplevel = null;
}

// This event is raised by the backend when a new output (aka a display or
// monitor) becomes available.
fn new_output(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    log.info("New output", .{});

    const wlr_output: [*c]c.wlr_output = @ptrCast(@alignCast(data));

    // Configures the output created by the backend to use our allocator
    // and our renderer. Must be done once, before committing the output.
    _ = c.wlr_output_init_render(wlr_output, wlr_allocator, wlr_renderer);

    const output: *Output = Output.new(wlr_output) catch @panic("OOM");
    c.wl_list_insert(&outputs, &output.link);

    // Adds this to the output layout. The add_auto function arranges outputs
    // from left-to-right in the order they appear. A more sophisticated
    // compositor would let the user configure the arrangement of outputs in the
    // layout.
    //
    // The output layout utility automatically adds a wl_output global to the
    // display, which Wayland clients can see to find out information about the
    // output (such as DPI, scale factor, manufacturer, etc).
    const wlr_output_layout_output: [*c]c.wlr_output_layout_output =
        c.wlr_output_layout_add_auto(wlr_output_layout, wlr_output);
    const wlr_scene_output: [*c]c.wlr_scene_output = c.wlr_scene_output_create(wlr_scene, wlr_output);
    c.wlr_scene_output_layout_add_output(wlr_scene_layout, wlr_output_layout_output, wlr_scene_output);
}

// This event is raised when a client creates a new toplevel (application window).
fn new_xdg_toplevel(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const wlr_xdg_toplevel: [*c]c.wlr_xdg_toplevel = @ptrCast(@alignCast(data));
    const tl: *XdgToplevel = XdgToplevel.new(wlr_xdg_toplevel) catch @panic("OOM");
    c.wl_list_insert(&toplevels, &tl.link);
}

// This event is raised when a client creates a new popup.
fn new_xdg_popup(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const wlr_xdg_popup: [*c]c.wlr_xdg_popup = @ptrCast(@alignCast(data));
    _ = XdgPopup.new(wlr_xdg_popup) catch @panic("OOM");
}

// This event is forwarded by the cursor when a pointer emits a relative pointer motion event (i.e. a delta).
fn cursor_motion(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_pointer_motion_event = @ptrCast(@alignCast(data));
    c.wlr_cursor_move(wlr_cursor, &event.*.pointer.*.base, event.*.delta_x, event.*.delta_y);
    cursor_mode.processCursorMotion(event.*.time_msec);
}

// This event is forwarded by the cursor when a pointer emits an absolute motion event, from 0..1 on each axis.
// This happens, for example, when wlroots is running under a Wayland window rather than KMS+DRM, and you move
// the mouse over the window. You could enter the window from any edge, so we have to warp the mouse there.
// There is also some hardware which emits these events.
fn cursor_motion_absolute(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_pointer_motion_absolute_event = @ptrCast(@alignCast(data));
    c.wlr_cursor_warp_absolute(wlr_cursor, &event.*.pointer.*.base, event.*.x, event.*.y);
    cursor_mode.processCursorMotion(event.*.time_msec);
}

// This event is forwarded by the cursor when a pointer emits a button event.
fn cursor_button(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_pointer_button_event = @ptrCast(@alignCast(data));
    // Notify the client with pointer focus that a button press has occurred
    _ = c.wlr_seat_pointer_notify_button(wlr_seat, event.*.time_msec, event.*.button, event.*.state);

    switch (event.*.state) {
        // If you released any buttons, we exit interactive move/resize mode.
        c.WL_POINTER_BUTTON_STATE_RELEASED => resetCursorMode(),
        // Focus that client if the button was pressed.
        c.WL_POINTER_BUTTON_STATE_PRESSED => {
            var sx: f64 = undefined;
            var sy: f64 = undefined;
            var surface: [*c]c.wlr_surface = null;
            const toplevel: ?*XdgToplevel = .desktopToplevelAt(wlr_cursor.*.x, wlr_cursor.*.y, &surface, &sx, &sy);
            if (toplevel) |tl| tl.focus();
        },
        else => unreachable,
    }
}

// This event is forwarded by the cursor when a pointer emits an axis event,
// for example when you move the scroll wheel.
fn cursor_axis(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_pointer_axis_event = @ptrCast(@alignCast(data));
    // Notify the client with pointer focus of the axis event.
    c.wlr_seat_pointer_notify_axis(
        wlr_seat,
        event.*.time_msec,
        event.*.orientation,
        event.*.delta,
        event.*.delta_discrete,
        event.*.source,
        event.*.relative_direction,
    );
}

// This event is forwarded by the cursor when a pointer emits an frame
// event. Frame events are sent after regular pointer events to group
// multiple events together. For instance, two axis events may happen at the
// same time, in which case a frame event won't be sent in between.
fn cursor_frame(_: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    // Notify the client with pointer focus of the frame event.
    c.wlr_seat_pointer_notify_frame(wlr_seat);
}

// This event is raised by the backend when a new input device becomes available.
fn new_input(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const device: [*c]c.wlr_input_device = @ptrCast(@alignCast(data));
    log.info("New input device: {s}", .{device.*.name});
    switch (device.*.type) {
        c.WLR_INPUT_DEVICE_KEYBOARD => _ = Keyboard.new(device) catch @panic("OOM"),
        c.WLR_INPUT_DEVICE_POINTER =>
        // We don't do anything special with pointers. All of our pointer handling is
        // proxied through wlr_cursor. On another compositor, you might take this
        // opportunity to do libinput configuration on the device to set acceleration, etc.
        c.wlr_cursor_attach_input_device(wlr_cursor, device),
        else => {},
    }
    // We need to let the wlr_seat know what our capabilities are, which is
    // communiciated to the client. In TinyWL we always have a cursor, even if
    // there are no pointer devices, so we always include that capability.
    var caps: u32 = c.WL_SEAT_CAPABILITY_POINTER;
    if (0 == c.wl_list_empty(&keyboards)) caps |= c.WL_SEAT_CAPABILITY_KEYBOARD;
    c.wlr_seat_set_capabilities(wlr_seat, caps);
}

// This event is raised by the seat when a client provides a cursor image.
fn request_cursor(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_seat_pointer_request_set_cursor_event = @ptrCast(@alignCast(data));
    // This can be sent by any client, so we check to make sure this one is
    // actually has pointer focus first.
    if (event.*.seat_client != wlr_seat.*.pointer_state.focused_client) return;
    // Once we've vetted the client, we can tell the cursor to use the provided surface
    // as the cursor image. It will set the hardware cursor on the output that it's
    // currently on and continue to do so as the cursor moves between outputs.
    c.wlr_cursor_set_surface(wlr_cursor, event.*.surface, event.*.hotspot_x, event.*.hotspot_y);
}

// This event is raised when the pointer focus is changed, including when the client is closed.
fn pointer_focus_change(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_seat_pointer_focus_change_event = @ptrCast(@alignCast(data));
    // We set the cursor image to its default if target surface is null.
    if (null == event.*.new_surface)
        c.wlr_cursor_set_xcursor(wlr_cursor, wlr_cursor_manager, "default");
}

// This event is raised by the seat when a client wants to set the selection,
// usually when the user copies something. wlroots allows compositors to
// ignore such requests if they so choose, but in tinywl we always honor.
fn request_set_selection(_: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event: [*c]c.wlr_seat_request_set_selection_event = @ptrCast(@alignCast(data));
    c.wlr_seat_set_selection(wlr_seat, event.*.source, event.*.serial);
}

pub fn spawn(argv: [*c]const [*c]u8) void {
    const pid = c.fork();
    if (pid < 0) {
        std.log.err("FORK FAILED", .{});
        return;
    }

    if (pid != 0)
        return;

    _ = c.setsid();
    _ = c.execvp(argv[0], argv);

    c._exit(127);
}
