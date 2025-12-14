/// WiFi Ping Demo - responds to ICMP echo requests
/// Test with: ping 192.168.1.200
const std = @import("std");
const microzig = @import("microzig");
const cyw43 = microzig.drivers.wireless.cyw43;
const wifi_config = @import("wifi_config.zig");
const net = @import("net.zig");
const usb_logging = @import("usb_logging.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;
const pio = rp2xxx.pio;

pub const microzig_options = microzig.Options{
    .log_level = .info,
    .logFn = usb_logging.logFn,
};

const log = std.log.scoped(.main);

// Network config - edit this
const our_ip: net.Ipv4Address = .{ 192, 168, 1, 200 };

// Pico 2 W pins
const PIN_WL_REG_ON = gpio.num(23);
const PIN_WL_DATA = gpio.num(24);
const PIN_WL_CS = gpio.num(25);
const PIN_WL_CLK = gpio.num(29);

fn delay_ms(ms: u32) void {
    time.sleep_ms(ms);
}

pub fn main() !void {
    usb_logging.init();

    var pio_spi = rp2xxx.cyw49_pio_spi.init(.{
        .pio = pio.num(0),
        .cs_pin = PIN_WL_CS,
        .io_pin = PIN_WL_DATA,
        .clk_pin = PIN_WL_CLK,
    }) catch |err| {
        log.err("PIO SPI init failed: {}", .{err});
        return;
    };

    PIN_WL_REG_ON.set_function(.sio);
    PIN_WL_REG_ON.set_direction(.out);

    var spi = pio_spi.cyw43_spi();
    var pwr = rp2xxx.drivers.GPIO_Device.init(PIN_WL_REG_ON);
    var bus = microzig.drivers.wireless.cyw43_bus.Cyw43_Bus{
        .pwr_pin = pwr.digital_io(),
        .spi = &spi,
        .internal_delay_ms = &delay_ms,
    };

    // Wait for USB to enumerate, then flush buffered logs
    var counter: u32 = 0;
    var last_time: u64 = time.get_time_since_boot().to_us();
    while (counter < 5) {
        usb_logging.task();
        const now = time.get_time_since_boot().to_us();
        if (now - last_time > 1_000_000) {
            last_time = now;
            counter += 1;
        }
    }
    usb_logging.flushBuffer();

    // Init
    var runner = cyw43.init(&bus, &delay_ms) catch |err| {
        log.err("CYW43 init failed: {}", .{err});
        return;
    };

    var wifi = runner.wifi();

    wifi.enable("GB") catch |err| {
        log.err("WiFi enable failed: {}", .{err});
        return;
    };

    const mac = wifi.get_mac_address() catch |err| {
        log.err("Failed to get MAC: {}", .{err});
        return;
    };
    log.info("MAC: {x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}", .{
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
    });

    // Connect
    log.info("Joining {s}...", .{wifi_config.WIFI_SSID});
    wifi.join(wifi_config.WIFI_SSID, wifi_config.WIFI_PASSWORD, .wpa2_psk) catch |err| {
        log.err("WiFi join failed: {}", .{err});
        return;
    };

    // Wait for connection (10s timeout)
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        _ = runner.run();
        if (wifi.is_connected()) break;
        delay_ms(100);
        usb_logging.task();
    }

    if (!wifi.is_connected()) {
        log.err("Connection timeout", .{});
        return;
    }

    log.info("Connected! IP: {}.{}.{}.{}", .{ our_ip[0], our_ip[1], our_ip[2], our_ip[3] });
    wifi.gpio_set(0, true) catch {}; // LED on

    var net_stack = net.NetStack.init(.{
        .mac = mac,
        .ip = our_ip,
    });

    while (true) {
        _ = runner.run();
        if (runner.get_rx_frame()) |frame| {
            // Handle ethernet dataframes as you wish here.
            if (net_stack.handleFrame(frame)) |response| {
                wifi.send(response) catch {};
            }
        }
        usb_logging.task();
    }
}
