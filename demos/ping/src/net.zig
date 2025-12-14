const std = @import("std");
const ethernet = @import("ethernet.zig");

const log = std.log.scoped(.net);

/// IPv4 address (4 bytes)
pub const Ipv4Address = [4]u8;

/// Network configuration
pub const Config = struct {
    mac: ethernet.MacAddress,
    ip: Ipv4Address,
};

/// ARP packet structure (28 bytes)
pub const ArpPacket = extern struct {
    htype: [2]u8, // Hardware type (1 = Ethernet) - big endian
    ptype: [2]u8, // Protocol type (0x0800 = IPv4) - big endian
    hlen: u8, // Hardware address length (6)
    plen: u8, // Protocol address length (4)
    oper: [2]u8, // Operation (1 = request, 2 = reply) - big endian
    sha: ethernet.MacAddress, // Sender hardware address
    spa: Ipv4Address, // Sender protocol address
    tha: ethernet.MacAddress, // Target hardware address
    tpa: Ipv4Address, // Target protocol address

    pub const REQUEST: u16 = 1;
    pub const REPLY: u16 = 2;

    pub fn getOper(self: *const ArpPacket) u16 {
        return (@as(u16, self.oper[0]) << 8) | self.oper[1];
    }
};

/// IPv4 header (20 bytes minimum, no options)
pub const Ipv4Header = extern struct {
    version_ihl: u8, // Version (4 bits) + IHL (4 bits)
    tos: u8, // Type of service
    total_length: [2]u8, // Total length (big-endian)
    identification: [2]u8,
    flags_fragment: [2]u8,
    ttl: u8,
    protocol: u8, // 1 = ICMP
    checksum: [2]u8,
    src: Ipv4Address,
    dst: Ipv4Address,

    pub const PROTOCOL_ICMP: u8 = 1;

    pub fn getHeaderLength(self: *const Ipv4Header) usize {
        return @as(usize, self.version_ihl & 0x0F) * 4;
    }

    pub fn setChecksum(self: *Ipv4Header, val: u16) void {
        self.checksum[0] = @intCast(val & 0xFF);
        self.checksum[1] = @intCast((val >> 8) & 0xFF);
    }
};

/// ICMP header
pub const IcmpHeader = packed struct {
    type: u8,
    code: u8,
    checksum: u16,
    identifier: u16,
    sequence: u16,

    pub const ECHO_REPLY: u8 = 0;
    pub const ECHO_REQUEST: u8 = 8;
};

/// Network stack state (ARP + ICMP only)
pub const NetStack = struct {
    config: Config,
    tx_buf: [1500]u8 = undefined,

    pub fn init(config: Config) NetStack {
        return .{ .config = config };
    }

    /// Handle an incoming ethernet frame
    /// Returns a response frame to send (if any)
    pub fn handleFrame(self: *NetStack, frame_data: []const u8) ?[]const u8 {
        const frame = ethernet.parse(frame_data) orelse return null;

        const dst = frame.dst();
        const is_broadcast = ethernet.isBroadcast(dst);
        const is_ours = ethernet.macEqual(dst, self.config.mac);

        if (!is_ours and !is_broadcast) {
            return null;
        }

        return switch (frame.ethertype()) {
            .arp => self.handleArp(frame),
            .ipv4 => self.handleIpv4(frame),
            else => null,
        };
    }

    /// Handle ARP packet
    fn handleArp(self: *NetStack, frame: ethernet.Frame) ?[]const u8 {
        if (frame.payload.len < @sizeOf(ArpPacket)) {
            return null;
        }

        const arp: *const ArpPacket = @ptrCast(@alignCast(frame.payload.ptr));

        // Only respond to ARP requests for our IP
        if (arp.getOper() != ArpPacket.REQUEST) {
            return null;
        }

        if (!std.mem.eql(u8, &arp.tpa, &self.config.ip)) {
            return null;
        }

        log.info("ARP request for our IP from {}.{}.{}.{}", .{
            arp.spa[0], arp.spa[1], arp.spa[2], arp.spa[3],
        });

        // Build ARP reply
        var arp_reply: ArpPacket = .{
            .htype = @bitCast(std.mem.nativeToBig(u16, 1)), // Ethernet
            .ptype = @bitCast(std.mem.nativeToBig(u16, 0x0800)), // IPv4
            .hlen = 6,
            .plen = 4,
            .oper = @bitCast(std.mem.nativeToBig(u16, ArpPacket.REPLY)),
            .sha = self.config.mac,
            .spa = self.config.ip,
            .tha = arp.sha,
            .tpa = arp.spa,
        };

        const arp_bytes = std.mem.asBytes(&arp_reply);
        const frame_len = ethernet.build(
            &self.tx_buf,
            arp.sha,
            self.config.mac,
            .arp,
            arp_bytes,
        ) orelse return null;

        log.info("Sending ARP reply", .{});
        return self.tx_buf[0..frame_len];
    }

    /// Handle IPv4 packet
    fn handleIpv4(self: *NetStack, frame: ethernet.Frame) ?[]const u8 {
        if (frame.payload.len < @sizeOf(Ipv4Header)) {
            return null;
        }

        const ip: *const Ipv4Header = @ptrCast(@alignCast(frame.payload.ptr));

        // Check if packet is for us
        if (!std.mem.eql(u8, &ip.dst, &self.config.ip)) {
            return null;
        }

        const ip_header_len = ip.getHeaderLength();
        if (frame.payload.len < ip_header_len) {
            return null;
        }

        const ip_payload = frame.payload[ip_header_len..];

        if (ip.protocol == Ipv4Header.PROTOCOL_ICMP) {
            return self.handleIcmp(frame, ip, ip_payload);
        }

        return null;
    }

    /// Handle ICMP packet
    fn handleIcmp(self: *NetStack, frame: ethernet.Frame, ip: *const Ipv4Header, icmp_data: []const u8) ?[]const u8 {
        if (icmp_data.len < @sizeOf(IcmpHeader)) {
            return null;
        }

        const icmp: *const IcmpHeader = @ptrCast(@alignCast(icmp_data.ptr));

        if (icmp.type != IcmpHeader.ECHO_REQUEST) {
            return null;
        }

        log.info("ICMP echo request from {}.{}.{}.{}", .{
            ip.src[0], ip.src[1], ip.src[2], ip.src[3],
        });

        // Build ICMP echo reply
        const ip_header_len: usize = 20;
        const total_ip_len = ip_header_len + icmp_data.len;
        const eth_header_len = @sizeOf(ethernet.Header);
        var offset: usize = eth_header_len;

        // Build IP header
        const ip_hdr: *Ipv4Header = @ptrCast(@alignCast(self.tx_buf[offset..].ptr));
        ip_hdr.* = .{
            .version_ihl = 0x45,
            .tos = 0,
            .total_length = @bitCast(std.mem.nativeToBig(u16, @intCast(total_ip_len))),
            .identification = .{ 0, 0 },
            .flags_fragment = .{ 0, 0 },
            .ttl = 64,
            .protocol = Ipv4Header.PROTOCOL_ICMP,
            .checksum = .{ 0, 0 },
            .src = self.config.ip,
            .dst = ip.src,
        };
        ip_hdr.setChecksum(ipChecksum(std.mem.asBytes(ip_hdr)));

        offset += ip_header_len;

        // Copy ICMP data and modify type to reply
        @memcpy(self.tx_buf[offset..][0..icmp_data.len], icmp_data);
        self.tx_buf[offset] = IcmpHeader.ECHO_REPLY;
        self.tx_buf[offset + 2] = 0; // Zero checksum
        self.tx_buf[offset + 3] = 0;

        // Calculate ICMP checksum
        const icmp_checksum = ipChecksum(self.tx_buf[offset..][0..icmp_data.len]);
        self.tx_buf[offset + 2] = @intCast(icmp_checksum & 0xFF);
        self.tx_buf[offset + 3] = @intCast((icmp_checksum >> 8) & 0xFF);

        offset += icmp_data.len;

        // Build ethernet header
        const eth_hdr: *ethernet.Header = @ptrCast(@alignCast(self.tx_buf[0..].ptr));
        eth_hdr.dst = frame.src();
        eth_hdr.src = self.config.mac;
        eth_hdr.setEthertype(.ipv4);

        log.info("Sending ICMP echo reply", .{});
        return self.tx_buf[0..offset];
    }
};

/// Calculate IP/ICMP checksum
fn ipChecksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;

    while (i + 1 < data.len) : (i += 2) {
        const word: u16 = @as(u16, data[i]) | (@as(u16, data[i + 1]) << 8);
        sum += word;
    }

    if (i < data.len) {
        sum += data[i];
    }

    while (sum >> 16 != 0) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }

    return ~@as(u16, @intCast(sum & 0xFFFF));
}
