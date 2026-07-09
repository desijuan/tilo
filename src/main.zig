const std = @import("std");
const posix = std.posix;

const c = @import("c.zig").c;

const Server = @import("Server.zig");

fn sig_handler(sig: posix.SIG) callconv(.c) void {
    return switch (sig) {
        posix.SIG.CHLD => while (posix.system.waitpid(-1, null, posix.W.NOHANG) > 0) {},
        posix.SIG.INT, posix.SIG.TERM => {
            std.debug.print("\n", .{});
            Server.terminate();
        },
        else => unreachable,
    };
}

pub fn main() !void {
    const sa = posix.Sigaction{
        .handler = .{ .handler = sig_handler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };

    inline for ([3]posix.SIG{
        posix.SIG.CHLD, posix.SIG.INT, posix.SIG.TERM,
    }) |sig| posix.sigaction(sig, &sa, null);

    c.wlr_log_init(c.WLR_DEBUG, null);

    try Server.init();
    defer Server.deinit();

    Server.run();
}
