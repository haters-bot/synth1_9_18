# ESP-01S Wi-Fi ↔ UART bridge (1 Mbps)

This is a raw byte-stream bridge for the UI FPGA phone protocol. It replaces
the generic Ai-Thinker AT firmware when the bridge firmware is installed; the
FPGA keeps its existing framed protocol, CRC, retry, recording, and resume logic.

## Defaults

- Wi-Fi AP: `FPGA-ESP01S`
- Password: `PianoLink1M`
- AP address: `192.168.4.1`
- TCP server: port `333`, one client
- UART0: `1,000,000 baud`, 8 data bits, no parity, 1 stop bit
- ESP-01S flash target: 1 MiB DOUT, no filesystem

The app first joins the module's AP in Android Wi-Fi settings, then chooses
Wi-Fi TCP and connects to `192.168.4.1:333`. TCP is a byte stream; packet
boundaries are supplied by the existing FPGA protocol decoder, not by Wi-Fi.
The ESP does not parse AT text or alter application payloads.

## Wiring

With all boards powered off:

| ESP-01S | UI board |
|---|---|
| TX / GPIO1 | F16 (UI UART RX) |
| RX / GPIO3 | F14 (UI UART TX) |
| GND | common ground |
| 3V3 | regulated 3.3 V supply sized for Wi-Fi current bursts |
| EN, RST, IO0 | normal-boot pull-ups; use the existing module resistors where fitted |
| IO2 / GPIO2 | Leave externally unconnected on the standard ESP-01S; used for its blue LED |

Do not feed the module from a weak FPGA I/O supply or apply 5 V to its pins.
Disconnect HC-07 TX/RX from F14/F16 while using this bridge. The ESP-01S
UART0 emits ROM boot text at reset; the FPGA packet parser must ignore bytes
before a CRC-valid HELLO locks the session.

**Remove any direct GPIO2-to-3V3 or GPIO2-to-GND wire before flashing this
version.** Normal-boot straps are sampled before `setup()`; the sketch then
drives GPIO2 low to light the module's active-low blue LED. A hard tie to VCC
would contend with that output. Standard ESP-01S modules include startup
pull-ups; other module revisions must be checked against their schematic.

## Blue status LED

| Pattern | Meaning |
|---|---|
| About 0.6 s on at boot | The bridge sketch has started |
| One brief flash every 2 s | AP started, no phone associated |
| Two brief flashes every 2 s | Phone joined Wi-Fi, TCP not connected |
| Steady on | TCP connected, currently little/no raw-byte traffic |
| Brief dark pulses while otherwise on | Recent UART/TCP byte transfer, including status polling |
| Equal on/off fast flashing | AP setup failed, or for 3 s after UART overrun / 1 s TCP transmit stall |

The LED shows Wi-Fi/TCP/byte-transfer state. It does **not** verify MIDI CRC,
FPGA HELLO acceptance or keyboard calibration; those remain App/FPGA checks.
If the AP disappears entirely, check supply voltage at the module and resets.
LED support and software backpressure handling cannot repair a weak supply.

## Scheduling and backpressure

- Each loop consumes/sends at most 512 bytes per direction and calls `yield()`;
  continuously busy UART input can no longer monopolize a drain-until-empty loop.
- Pending TCP output is drained before accepting more UART input. A full 8 KiB
  queue temporarily leaves unread bytes in the 4 KiB UART RX buffer instead of
  immediately throwing bytes away and disconnecting.
- Partial/zero-length UART and TCP writes preserve the unsent bytes.
- Actual UART buffer overrun or 1000 ms without TCP output progress closes the
  damaged/stalled stream; the phone can resume from its committed PCM block.
  Framed protocol bytes and 1 Mbps 8N1 settings remain unchanged.
- Firmware emits no diagnostic text on UART0. AP initialization failure retries
  at 5-second intervals, without repeatedly restarting a healthy hotspot.

## Build and flash

Build with PlatformIO (`pio run`, platform pinned to `espressif8266@4.2.1`,
Arduino ESP8266 core 3.1.2). Confirm the module flash capacity before
using the `esp01_1m` target. Use the ESP-01 USB programmer, not the Gowin JTAG.
For serial boot, GPIO0 must be low when reset is released; the programmer's
PROG switch/button may do this automatically. After flashing, restore GPIO0
high and reset for normal operation. This project intentionally does not
contain or execute a flashing script.

Host tests compile the production sketch with deterministic UART/Wi-Fi models:

```text
g++ -std=c++11 -Wall -Wextra -Werror -I test/host/fakes test/host/test_bridge.cpp -o test_bridge
```

Run the resulting executable outside the source tree. These tests check byte
preservation, scheduling limits, LED states and reconnect handling; they do not
model power, RF, lwIP behavior or prove actual ESP/phone stability.

## 1 Mbps acceptance still required

The source selects 1 Mbps UART, but this is not a measured link result. Before
using recordings, verify on the bench:

1. AP association and TCP connect survive screen sleep and repeated reconnects.
2. UI HELLO/ACK and status report `1000000` baud.
3. Run a long bidirectional byte-pattern test with CRC/error counters and no
   missing/duplicated bytes; inspect UART at both ends with a logic analyzer.
4. Transfer a complete recording and test disconnect/resume from the last
   phone-committed block.
5. Measure sustained B/s, ESP resets, queue overflow, and Wi-Fi disconnects.

No hardware programming or 1 Mbps physical test is implied by compiling the
firmware or the FPGA/App source.
