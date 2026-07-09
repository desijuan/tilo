const std = @import("std");
const log = std.log;

const a = std.heap.c_allocator;

const c = @import("c.zig").c;

const Server = @import("Server.zig");

const Output = @This();

link: c.wl_list,

wlr_output: [*c]c.wlr_output,

l_frame: c.wl_listener,
l_request_state: c.wl_listener,
l_destroy: c.wl_listener,

pub fn new(wlr_output: [*c]c.wlr_output) error{OutOfMemory}!*Output {
    // The output may be disabled, switch it on.
    var wlr_output_state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&wlr_output_state);
    c.wlr_output_state_set_enabled(&wlr_output_state, true);

    // Some backends don't have modes. DRM+KMS does, and we need to set a mode before we can use the
    // output. The mode is a tuple of (width, height, refresh rate), and each monitor supports only
    // a specific set of modes. We just pick the monitor's preferred mode, a more sophisticated
    // compositor would let the user configure it.
    const wlr_output_mode: [*c]c.wlr_output_mode = c.wlr_output_preferred_mode(wlr_output);
    if (null != wlr_output_mode) c.wlr_output_state_set_mode(&wlr_output_state, wlr_output_mode);

    // Atomically applies the new output state.
    _ = c.wlr_output_commit_state(wlr_output, &wlr_output_state);
    c.wlr_output_state_finish(&wlr_output_state);

    const output: *Output = try a.create(Output);
    errdefer a.destroy(output);

    output.wlr_output = wlr_output;

    output.l_frame.notify = Output.frame;
    c.wl_signal_add(&wlr_output.*.events.frame, &output.l_frame);

    output.l_request_state.notify = Output.request_state;
    c.wl_signal_add(&wlr_output.*.events.request_state, &output.l_request_state);

    output.l_destroy.notify = Output.destroy;
    c.wl_signal_add(&wlr_output.*.events.destroy, &output.l_destroy);

    return output;
}

// This function is called every time an output is ready to display a frame,
// generally at the output's refresh rate (e.g. 60Hz).
fn frame(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const output: *Output = @fieldParentPtr("l_frame", @as(*c.wl_listener, @ptrCast(listener)));

    const scene_output: [*c]c.wlr_scene_output = c.wlr_scene_get_scene_output(Server.wlr_scene, output.wlr_output);

    // Render the scene if needed and commit the output.
    _ = c.wlr_scene_output_commit(scene_output, null);

    var now: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wlr_scene_output_send_frame_done(scene_output, &now);
}

// This function is called when the backend requests a new state for the output.
// For example, Wayland and X11 backends request a new mode when the output window is resized.
fn request_state(listener: [*c]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const output: *Output = @fieldParentPtr("l_request_state", @as(*c.wl_listener, @ptrCast(listener)));
    const event: [*c]c.wlr_output_event_request_state = @ptrCast(@alignCast(data));
    _ = c.wlr_output_commit_state(output.wlr_output, event.*.state);
}

fn destroy(listener: [*c]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
    const output: *Output = @fieldParentPtr("l_destroy", @as(*c.wl_listener, @ptrCast(listener)));

    c.wl_list_remove(&output.l_frame.link);
    c.wl_list_remove(&output.l_request_state.link);
    c.wl_list_remove(&output.l_destroy.link);

    c.wl_list_remove(&output.link);

    a.destroy(output);
}
