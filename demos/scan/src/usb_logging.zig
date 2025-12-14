const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;

// Import USB from core directly to avoid broken hal re-export
const usb = microzig.core.usb;

// CDC driver from core
const UsbSerial = usb.drivers.cdc.CdcClassDriver(.{ .max_packet_size = 64 });

// USB device using the new Polled API
pub var usb_dev: rp2xxx.usb.Polled(
    usb.Config{
        .device_descriptor = .{
            .bcd_usb = .from(0x0200),
            .device_triple = .{
                .class = .Miscellaneous,
                .subclass = 2,
                .protocol = 1,
            },
            .max_packet_size0 = 64,
            .vendor = .from(0x2E8A),
            .product = .from(0x000A),
            .bcd_device = .from(0x0100),
            .manufacturer_s = 1,
            .product_s = 2,
            .serial_s = 3,
            .num_configurations = 1,
        },
        .string_descriptors = &.{
            .from_lang(.English),
            .from_str("Raspberry Pi"),
            .from_str("Pico 2 W WiFi Demo"),
            .from_str("12345678"),
            .from_str("Board CDC"),
        },
        .configurations = &.{.{
            .num = 1,
            .configuration_s = 0,
            .attributes = .{ .self_powered = true },
            .max_current_ma = 100,
            .Drivers = struct { serial: UsbSerial },
        }},
    },
    .{},
) = undefined;

// Logging state
var usb_tx_buff: [1024]u8 = undefined;
var log_buffer: [8192]u8 = undefined;
var log_buffer_pos: usize = 0;
var log_buffering: bool = true;
var log_seq: u32 = 0;

/// Initialize USB device
pub fn init() void {
    usb_dev = .init();

    // Process initial USB events
    for (0..10) |_| {
        usb_dev.poll();
    }
}

/// Call this periodically to process USB events
pub fn task() void {
    usb_dev.poll();
}

/// Flush buffered logs (call after USB is ready, typically after a few seconds)
pub fn flushBuffer() void {
    if (!log_buffering) return;
    log_buffering = false;

    if (log_buffer_pos == 0) return;

    const drivers = usb_dev.controller.drivers() orelse return;

    const data = log_buffer[0..log_buffer_pos];
    var start: usize = 0;

    for (data, 0..) |c, i| {
        if (c == '\n') {
            const line = data[start .. i + 1];
            var written: usize = 0;
            while (written < line.len) {
                const rem = drivers.serial.write(line[written..]);
                written = line.len - rem.len;
                usb_dev.poll();
            }
            _ = drivers.serial.write_flush();
            for (0..20) |_| {
                usb_dev.poll();
            }
            time.sleep_ms(50);
            start = i + 1;
        }
    }
    log_buffer_pos = 0;
}

/// Log function for std.log integration
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const scope_txt = if (scope == .default) "" else "(" ++ @tagName(scope) ++ ") ";
    const prefix = level_txt ++ " " ++ scope_txt;

    log_seq +%= 1;

    const seq_text = std.fmt.bufPrint(&usb_tx_buff, "[{d:0>4}] " ++ prefix, .{log_seq}) catch return;
    const pos = seq_text.len;

    const msg_text = std.fmt.bufPrint(usb_tx_buff[pos..], fmt ++ "\r\n", args) catch return;
    const total_len = pos + msg_text.len;

    if (log_buffering) {
        const space = log_buffer.len - log_buffer_pos;
        const to_copy = @min(total_len, space);
        @memcpy(log_buffer[log_buffer_pos..][0..to_copy], usb_tx_buff[0..to_copy]);
        log_buffer_pos += to_copy;
    } else {
        if (usb_dev.controller.drivers()) |drivers| {
            var offset: usize = 0;
            while (offset < total_len) {
                const remaining = drivers.serial.write(usb_tx_buff[offset..total_len]);
                offset = total_len - remaining.len;
                usb_dev.poll();
            }
            _ = drivers.serial.write_flush();
            for (0..10) |_| {
                usb_dev.poll();
            }
            time.sleep_ms(5);
        }
    }
}
