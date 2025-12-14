const std = @import("std");

/// Ethernet frame ethertypes
pub const Ethertype = enum(u16) {
    ipv4 = 0x0800,
    arp = 0x0806,
    ipv6 = 0x86DD,
    _,
};

/// MAC address (6 bytes)
pub const MacAddress = [6]u8;

/// Broadcast MAC address
pub const BROADCAST_MAC: MacAddress = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

/// Ethernet frame header (14 bytes)
pub const Header = extern struct {
    dst: MacAddress,
    src: MacAddress,
    ethertype_bytes: [2]u8, // Big-endian

    pub fn getEthertype(self: *const Header) Ethertype {
        const val = (@as(u16, self.ethertype_bytes[0]) << 8) | self.ethertype_bytes[1];
        return @enumFromInt(val);
    }

    pub fn setEthertype(self: *Header, et: Ethertype) void {
        const val = @intFromEnum(et);
        self.ethertype_bytes[0] = @intCast((val >> 8) & 0xFF);
        self.ethertype_bytes[1] = @intCast(val & 0xFF);
    }
};

/// Parsed ethernet frame
pub const Frame = struct {
    header: *const Header,
    payload: []const u8,

    /// Get destination MAC
    pub fn dst(self: Frame) MacAddress {
        return self.header.dst;
    }

    /// Get source MAC
    pub fn src(self: Frame) MacAddress {
        return self.header.src;
    }

    /// Get ethertype
    pub fn ethertype(self: Frame) Ethertype {
        return self.header.getEthertype();
    }
};

/// Parse raw bytes into an ethernet frame
pub fn parse(data: []const u8) ?Frame {
    if (data.len < @sizeOf(Header)) {
        return null;
    }

    const header: *const Header = @ptrCast(@alignCast(data.ptr));
    const payload = data[@sizeOf(Header)..];

    return Frame{
        .header = header,
        .payload = payload,
    };
}

/// Build an ethernet frame into a buffer
/// Returns the number of bytes written
pub fn build(
    buf: []u8,
    dst: MacAddress,
    src: MacAddress,
    ethertype: Ethertype,
    payload: []const u8,
) ?usize {
    const total_len = @sizeOf(Header) + payload.len;
    if (buf.len < total_len) {
        return null;
    }

    // Write header
    const header: *Header = @ptrCast(@alignCast(buf.ptr));
    header.dst = dst;
    header.src = src;
    header.setEthertype(ethertype);

    // Write payload
    @memcpy(buf[@sizeOf(Header)..][0..payload.len], payload);

    return total_len;
}

/// Check if MAC addresses are equal
pub fn macEqual(a: MacAddress, b: MacAddress) bool {
    return std.mem.eql(u8, &a, &b);
}

/// Check if MAC is broadcast
pub fn isBroadcast(mac: MacAddress) bool {
    return macEqual(mac, BROADCAST_MAC);
}
