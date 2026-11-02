#include <Arduino.h>
#include <ESP8266WiFi.h>

#ifndef BRIDGE_UART_BAUD
#define BRIDGE_UART_BAUD 1000000
#endif
#ifndef TCP_PORT
#define TCP_PORT 333
#endif
#ifndef BRIDGE_LED_PIN
#define BRIDGE_LED_PIN 2
#endif

static const char WIFI_SSID[] = "FPGA-ESP01S";
static const char WIFI_PASSWORD[] = "PianoLink1M";
static constexpr size_t BRIDGE_BUFFER_SIZE = 8192;
static constexpr size_t BRIDGE_CHUNK_SIZE = 256;
// Bound work before returning to the Wi-Fi stack, including when UART RX is
// continuously busy. These are per-loop byte budgets, not baud-rate limits.
static constexpr size_t BRIDGE_LOOP_BYTES = 512;
static constexpr uint32_t TCP_STALL_MS = 1000;
static constexpr uint32_t ERROR_LED_MS = 3000;

static size_t smaller(size_t a, size_t b) { return a < b ? a : b; }

class ByteRing {
 public:
  bool push(uint8_t value) {
    if (size_ == BRIDGE_BUFFER_SIZE) return false;
    data_[tail_] = value;
    tail_ = (tail_ + 1) % BRIDGE_BUFFER_SIZE;
    ++size_;
    return true;
  }

  const uint8_t* front(size_t& count) const {
    count = size_ < BRIDGE_BUFFER_SIZE - head_ ? size_ : BRIDGE_BUFFER_SIZE - head_;
    return data_ + head_;
  }

  void discard(size_t count) {
    if (count > size_) count = size_;
    head_ = (head_ + count) % BRIDGE_BUFFER_SIZE;
    size_ -= count;
  }

  void clear() { head_ = tail_ = size_ = 0; }
  size_t size() const { return size_; }
  size_t free() const { return BRIDGE_BUFFER_SIZE - size_; }

 private:
  uint8_t data_[BRIDGE_BUFFER_SIZE]{};
  size_t head_ = 0;
  size_t tail_ = 0;
  size_t size_ = 0;
};

static WiFiServer server(TCP_PORT);
static WiFiClient peer;
static ByteRing uartToTcp;
static bool sessionOpen = false;
static bool apReady = false;
static uint32_t bootAt = 0;
static uint32_t apAttemptAt = 0;
static uint32_t lastTrafficAt = 0;
static bool trafficSeen = false;
static uint32_t lastTcpProgressAt = 0;
static uint32_t errorAt = 0;
static bool errorSeen = false;
// Preserve a short UART write instead of losing bytes already read from TCP.
static uint8_t tcpPending[BRIDGE_CHUNK_SIZE];
static size_t tcpPendingSize = 0;
static size_t tcpPendingOffset = 0;

static void noteTraffic(size_t count) {
  if (count) {
    lastTrafficAt = millis();
    trafficSeen = true;
  }
}

static void clearSession() {
  uartToTcp.clear();
  tcpPendingSize = tcpPendingOffset = 0;
  trafficSeen = false;
  lastTcpProgressAt = millis();
}

static void closePeer(bool error = false) {
  peer.stop();
  sessionOpen = false;
  clearSession();
  if (error) {
    errorAt = millis();
    errorSeen = true;
  }
}

static void updateLed() {
  const uint32_t now = millis();
  bool on;
  if (!apReady || (errorSeen && uint32_t(now - errorAt) < ERROR_LED_MS)) {
    on = (now % 200) < 100;  // Error: 5 flashes/second.
  } else if (uint32_t(now - bootAt) < 600) {
    on = true;  // A repeated startup pulse makes resets visible.
  } else if (sessionOpen) {
    // TCP connected: on. Raw-byte traffic: short dark pulses, visually
    // different from the equal on/off error pattern.
    on = !(trafficSeen && uint32_t(now - lastTrafficAt) < 200) ||
         (now % 250) >= 35;
  } else {
    const uint32_t phase = now % 2000;
    on = phase < 100 || (WiFi.softAPgetStationNum() > 0 &&
                        phase >= 250 && phase < 350);
  }
  digitalWrite(BRIDGE_LED_PIN, on ? LOW : HIGH);  // ESP-01S: active-low GPIO2.
}

static void startAccessPoint() {
  apAttemptAt = millis();
  const IPAddress address(192, 168, 4, 1);
  apReady = WiFi.softAPConfig(address, address, IPAddress(255, 255, 255, 0)) &&
            WiFi.softAP(WIFI_SSID, WIFI_PASSWORD, 1, false, 1);
  if (apReady) {
    server.begin();
    server.setNoDelay(true);
  }
}

static void acceptOneClient() {
  if (!server.hasClient()) return;
  WiFiClient incoming = server.accept();
  if (!incoming) return;
  if (sessionOpen && peer.connected()) {
    incoming.stop();
    return;
  }
  peer = incoming;
  peer.setNoDelay(true);
  sessionOpen = true;
  clearSession();
}

static void flushTcp(size_t& budget) {
  while (budget && uartToTcp.size()) {
    const size_t room = peer.availableForWrite();
    if (!room) break;
    size_t contiguous = 0;
    const uint8_t* data = uartToTcp.front(contiguous);
    const size_t count = smaller(smaller(contiguous, room),
                                 smaller(budget, BRIDGE_CHUNK_SIZE));
    const size_t written = peer.write(data, count);
    if (!written) break;
    uartToTcp.discard(written);
    budget -= written;
    lastTcpProgressAt = millis();
    noteTraffic(written);
    if (written != count) break;
  }
}

static void forwardUartToTcp() {
  size_t writeBudget = BRIDGE_LOOP_BYTES;
  flushTcp(writeBudget);  // Free queued bytes before accepting more UART data.
  size_t readBudget = BRIDGE_LOOP_BYTES;
  while (readBudget && uartToTcp.free() && Serial.available() > 0) {
    const size_t count = smaller(smaller(size_t(Serial.available()),
                                        uartToTcp.free()), readBudget);
    for (size_t i = 0; i < count; ++i) {
      const int byte = Serial.read();
      if (byte < 0) break;
      uartToTcp.push(static_cast<uint8_t>(byte));
    }
    readBudget -= count;
  }
  flushTcp(writeBudget);
  const uint32_t now = millis();
  if (!uartToTcp.size()) lastTcpProgressAt = now;
  // A full software queue is temporary backpressure, not immediate corruption.
  // An actual UART overrun is handled separately in loop().
  if (uartToTcp.size() && uint32_t(now - lastTcpProgressAt) >= TCP_STALL_MS)
    closePeer(true);
}

static void forwardTcpToUart() {
  size_t budget = BRIDGE_LOOP_BYTES;
  while (budget) {
    const size_t room = Serial.availableForWrite();
    if (!room) break;
    if (tcpPendingOffset == tcpPendingSize) {
      const size_t count = smaller(smaller(size_t(peer.available()),
                                          sizeof(tcpPending)), budget);
      if (!count) break;
      const int received = peer.read(tcpPending, count);
      if (received <= 0) break;
      tcpPendingOffset = 0;
      tcpPendingSize = size_t(received);
    }
    const size_t count = smaller(smaller(tcpPendingSize - tcpPendingOffset,
                                        room), budget);
    const size_t written = Serial.write(tcpPending + tcpPendingOffset, count);
    tcpPendingOffset += written;
    budget -= written;
    noteTraffic(written);
    if (written != count) break;
  }
}

void setup() {
  // Configure only after the ROM has sampled the boot straps. Never hard-wire
  // GPIO2 to VCC: the blue LED is driven low by this sketch after startup.
  digitalWrite(BRIDGE_LED_PIN, HIGH);
  pinMode(BRIDGE_LED_PIN, OUTPUT);
  bootAt = millis();
  // UART0 is dedicated to raw protocol bytes; never print diagnostics on it.
  Serial.setRxBufferSize(4096);
  Serial.begin(BRIDGE_UART_BAUD, SERIAL_8N1);
  Serial.setDebugOutput(false);

  WiFi.persistent(false);
  WiFi.setSleepMode(WIFI_NONE_SLEEP);
  WiFi.mode(WIFI_AP);
  startAccessPoint();
  updateLed();
}

void loop() {
  if (!apReady && uint32_t(millis() - apAttemptAt) >= 5000)
    startAccessPoint();

  const bool overrun = Serial.hasOverrun();
  if (sessionOpen && (!peer.connected() || overrun)) {
    // Once UART bytes are lost, preserve the phone's last committed block and
    // signal disconnect; pretending the byte stream stayed intact is unsafe.
    closePeer(overrun);
  }
  if (apReady) acceptOneClient();

  if (sessionOpen) {
    forwardTcpToUart();
    forwardUartToTcp();
  } else {
    size_t budget = BRIDGE_LOOP_BYTES;
    while (budget && Serial.available() > 0) {
      Serial.read();
      --budget;
    }
  }
  updateLed();
  yield();
}
