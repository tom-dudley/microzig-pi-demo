.PHONY: build copy flash monitor

build-ping:
	cd demos/ping && zig build

copy-ping:
	cp demos/ping/zig-out/firmware/wifi_ping.uf2 /Volumes/RP2350/

flash-ping: build-ping copy-ping

build-scan:
	cd demos/scan && zig build

copy-scan:
	cp demos/scan/zig-out/firmware/wifi_scan.uf2 /Volumes/RP2350/

flash-scan: build-scan copy-scan

monitor:
	./monitor.sh
