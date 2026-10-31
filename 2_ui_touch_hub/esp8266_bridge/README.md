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
| EN, RST, IO0, IO2 | normal-boot pull-ups to 3.3 V |

Do not feed the module from a weak FPGA I/O supply or apply 5 V to its pins.
Disconnect HC-07 TX/RX from F14/F16 while using this bridge. The ESP-01S
UART0 emits ROM boot text at reset; the FPGA packet parser must ignore bytes
before a CRC-valid HELLO locks the session.

## Build and flash

Build with PlatformIO (`pio run`). Confirm the module flash capacity before
using the `esp01_1m` target. Use the ESP-01 USB programmer, not the Gowin JTAG.
For serial boot, GPIO0 must be low when reset is released; the programmer's
PROG switch/button may do this automatically. After flashing, restore GPIO0
high and reset for normal operation. This project intentionally does not
contain or execute a flashing script.

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
