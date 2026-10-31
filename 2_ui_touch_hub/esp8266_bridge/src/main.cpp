#include <Arduino.h>
#include <ESP8266WiFi.h>

#ifndef BRIDGE_UART_BAUD
#define BRIDGE_UART_BAUD 1000000
#endif
#ifndef TCP_PORT
#define TCP_PORT 333
#endif

static const char WIFI_SSID[] = "FPGA-ESP01S";
static const char WIFI_PASSWORD[] = "PianoLink1M";
static constexpr size_t BRIDGE_BUFFER_SIZE = 8192;
static constexpr size_t BRIDGE_CHUNK_SIZE = 256;

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

 private:
  uint8_t data_[BRIDGE_BUFFER_SIZE]{};
  size_t head_ = 0;
  size_t tail_ = 0;
  size_t size_ = 0;
};

static WiFiServer server(TCP_PORT);
static WiFiClient peer;
static ByteRing uartToTcp;
static bool overflowed = false;

static void clearSession() {
  uartToTcp.clear();
  overflowed = false;
}

static void acceptOneClient() {
  WiFiClient incoming = server.available();
  if (!incoming) return;
  if (peer && peer.connected()) {
    incoming.stop();
    return;
  }
  peer = incoming;
  peer.setNoDelay(true);
  clearSession();
}

static void forwardUartToTcp() {
  uint8_t incoming[BRIDGE_CHUNK_SIZE];
  while (Serial.available() > 0) {
    size_t count = 0;
    while (count < sizeof(incoming) && Serial.available() > 0)
      incoming[count++] = static_cast<uint8_t>(Serial.read());
    for (size_t i = 0; i < count; ++i)
      if (!uartToTcp.push(incoming[i])) overflowed = true;
  }

  size_t available = peer.availableForWrite();
  while (available > 0 && uartToTcp.size() > 0) {
    size_t contiguous = 0;
    const uint8_t* data = uartToTcp.front(contiguous);
    size_t count = contiguous;
    if (count > available) count = available;
    if (count > BRIDGE_CHUNK_SIZE) count = BRIDGE_CHUNK_SIZE;
    if (!count) break;
    const size_t written = peer.write(data, count);
    uartToTcp.discard(written);
    available -= written;
    if (written != count) break;
  }
}

static void forwardTcpToUart() {
  uint8_t buffer[BRIDGE_CHUNK_SIZE];
  while (peer.available() > 0 && Serial.availableForWrite() > 0) {
    size_t count = peer.available();
    const size_t room = Serial.availableForWrite();
    if (count > sizeof(buffer)) count = sizeof(buffer);
    if (count > room) count = room;
    if (!count) break;
    const int received = peer.read(buffer, count);
    if (received <= 0) break;
    Serial.write(buffer, static_cast<size_t>(received));
  }
}

void setup() {
  // UART0 is dedicated to raw protocol bytes; never print diagnostics on it.
  Serial.setRxBufferSize(4096);
  Serial.begin(BRIDGE_UART_BAUD, SERIAL_8N1);

  WiFi.persistent(false);
  WiFi.setSleepMode(WIFI_NONE_SLEEP);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(WIFI_SSID, WIFI_PASSWORD, 1, false, 1);
  server.begin();
  server.setNoDelay(true);
}

void loop() {
  if (peer && !peer.connected()) {
    peer.stop();
    clearSession();
  }
  acceptOneClient();

  if (peer && peer.connected()) {
    forwardTcpToUart();
    forwardUartToTcp();
    // An 8 KiB queue absorbs brief Wi-Fi scheduling stalls. If sustained
    // congestion exceeds it, close TCP so the application detects the break
    // and can resume a recording from its last committed PCM block.
    if (overflowed) {
      peer.stop();
      clearSession();
    }
  } else {
    while (Serial.available() > 0) Serial.read();
  }
  yield();
}
