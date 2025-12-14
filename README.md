# WiFi Ping Demo for Raspberry Pi Pico 2 W

This is a little demo of a CYW43 driver for microzig, demonstrating connecting to a (WPA2) WiFi AP and responding to ICMP.

Note that this contains a few bits for USB debug logging which can be ignored.

## Usage

1. Configure WiFi credentials:
   ```bash
   cp src/wifi_config.zig.example src/wifi_config.zig
   # Edit src/wifi_config.zig with your SSID and password
   ```

2. Edit the IP address in `src/main.zig` if needed:
   ```zig
   const our_ip: net.Ipv4Address = .{ 192, 168, 1, 200 };
   ```

## Build and Flash

```bash
# Build
make build

# Flash (with RPi in BOOTSEL model)
make flash

# Monitor USB serial output
./monitor.sh
```

## Test
```bash
ping 192.168.1.200
```

## License

MIT
