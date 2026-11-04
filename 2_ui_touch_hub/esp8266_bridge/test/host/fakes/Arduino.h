#pragma once
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <deque>
#include <vector>

static constexpr int LOW=0, HIGH=1, OUTPUT=1, SERIAL_8N1=0;
static uint32_t fakeNow=0;
static unsigned fakeYields=0;
static int fakeLedPin=-1, fakeLedLevel=-1;
static std::vector<int> fakeLedWrites;
inline uint32_t millis() { return fakeNow; }
inline void yield() { ++fakeYields; }
inline void digitalWrite(int pin,int value) {
  fakeLedPin=pin;fakeLedLevel=value;fakeLedWrites.push_back(value);
}
inline void pinMode(int pin,int mode) {
  (void)pin;(void)mode;
}
class FakeSerial {
 public:
  std::deque<uint8_t> rx;
  std::vector<uint8_t> tx;
  size_t room=4096, writeLimit=4096, rxSize=0;
  unsigned baud=0;
  bool overrun=false, continuous=false, debug=true;
  size_t readCount=0;
  void setRxBufferSize(size_t value) { rxSize=value; }
  void begin(unsigned value,int config) { baud=value;(void)config; }
  void setDebugOutput(bool value) { debug=value; }
  bool hasOverrun() { bool value=overrun;overrun=false;return value; }
  int available() { return continuous ? 65536 : int(rx.size()); }
  int read() {
    if(continuous) { ++readCount;return 0x5A; }
    if(rx.empty())return -1;
    int value=rx.front();rx.pop_front();++readCount;return value;
  }
  int availableForWrite() { return int(room); }
  size_t write(const uint8_t* data,size_t count) {
    count=std::min(count,std::min(room,writeLimit));
    tx.insert(tx.end(),data,data+count);return count;
  }
};
static FakeSerial Serial;
