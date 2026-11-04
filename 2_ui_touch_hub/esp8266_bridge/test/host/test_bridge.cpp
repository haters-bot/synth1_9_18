// Host models exercise the actual sketch; they do not model RF, lwIP or power.
#include <cassert>
#include <iostream>
#include "../../src/main.cpp"

static void reset() {
  fakeNow=0;fakeYields=0;fakeLedWrites.clear();fakeLedPin=fakeLedLevel=-1;
  Serial=FakeSerial();WiFi=FakeWiFi();server=WiFiServer(TCP_PORT);
  peer=WiFiClient();uartToTcp.clear();sessionOpen=apReady=false;
  bootAt=apAttemptAt=lastTrafficAt=lastTcpProgressAt=errorAt=0;
  trafficSeen=errorSeen=false;tcpPendingOffset=tcpPendingSize=0;
  setup();
}
static std::shared_ptr<FakeSocket> connectPeer() {
  auto state=std::make_shared<FakeSocket>();
  server.waiting.push_back(WiFiClient(state));
  loop();assert(sessionOpen);return state;
}
static std::vector<uint8_t> pattern(size_t count) {
  std::vector<uint8_t> result(count);
  for(size_t i=0;i<count;++i)result[i]=uint8_t(i*37+(i>>8));
  return result;
}
static unsigned checks=0;
static void passed(const char* name) { ++checks;std::cout<<"PASS "<<name<<'\n'; }

int main() {
  reset();
  assert(fakeLedPin==2 && fakeLedWrites.front()==HIGH && fakeLedLevel==LOW);
  assert(Serial.baud==1000000 && Serial.rxSize==4096 && !Serial.debug);
  assert(apReady && WiFi.ssid=="FPGA-ESP01S" && Serial.tx.empty());
  passed("boot, active-low GPIO2, UART settings and no debug bytes");

  fakeNow=2001;updateLed();assert(fakeLedLevel==LOW);
  fakeNow=2260;updateLed();assert(fakeLedLevel==HIGH);
  WiFi.stations=1;updateLed();assert(fakeLedLevel==LOW);
  fakeNow=2400;updateLed();assert(fakeLedLevel==HIGH);
  passed("waiting heartbeat and associated-phone double flash");

  auto socket=connectPeer();fakeNow=3000;updateLed();assert(fakeLedLevel==LOW);
  noteTraffic(1);fakeNow=3010;updateLed();assert(fakeLedLevel==HIGH);
  fakeNow=3050;updateLed();assert(fakeLedLevel==LOW);
  fakeNow=3300;updateLed();assert(fakeLedLevel==LOW);
  passed("TCP connected LED and short dark traffic pulses");

  reset();socket=connectPeer();
  const auto bytes=pattern(20000);
  Serial.rx.insert(Serial.rx.end(),bytes.begin(),bytes.end());
  socket->input.insert(socket->input.end(),bytes.begin(),bytes.end());
  for(unsigned i=0;i<100;++i){loop();++fakeNow;}
  assert(socket->output==bytes && Serial.tx==bytes && sessionOpen);
  assert(fakeYields==101 && Serial.readCount==bytes.size());
  passed("20k simultaneous binary stream, FIFO wrap and per-loop Wi-Fi yields");

  reset();socket=connectPeer();Serial.writeLimit=3;socket->writeLimit=7;
  auto partial=pattern(800);
  Serial.rx.insert(Serial.rx.end(),partial.begin(),partial.end());
  socket->input.insert(socket->input.end(),partial.begin(),partial.end());
  for(unsigned i=0;i<1000;++i)loop();
  assert(Serial.tx==partial && socket->output==partial);
  passed("short UART/TCP writes preserve byte order and pending suffixes");

  reset();socket=connectPeer();Serial.writeLimit=0;socket->writeLimit=0;
  socket->input.push_back(0x47);Serial.rx.push_back(0x81);
  loop();assert(Serial.tx.empty() && socket->output.empty());
  Serial.writeLimit=4096;socket->writeLimit=65536;loop();
  assert(Serial.tx==std::vector<uint8_t>{0x47});
  assert(socket->output==std::vector<uint8_t>{0x81});
  passed("zero-length writes yield without losing buffered data");

  reset();socket=connectPeer();socket->room=0;
  auto burst=pattern(BRIDGE_BUFFER_SIZE+512);
  Serial.rx.insert(Serial.rx.end(),burst.begin(),burst.end());
  for(unsigned i=0;i<30;++i)loop();
  assert(sessionOpen && uartToTcp.size()==BRIDGE_BUFFER_SIZE);
  assert(Serial.rx.size()==512 && !errorSeen);
  socket->room=65536;
  for(unsigned i=0;i<30;++i)loop();
  assert(sessionOpen && socket->output==burst && Serial.rx.empty());
  passed("temporary full queue retains extra UART data and recovers without disconnect");

  reset();socket=connectPeer();Serial.continuous=true;
  size_t before=Serial.readCount;loop();
  assert(Serial.readCount-before==BRIDGE_LOOP_BYTES && fakeYields==2);
  passed("continuous UART source has bounded work while connected");

  reset();Serial.continuous=true;loop();
  assert(Serial.readCount==BRIDGE_LOOP_BYTES && fakeYields==1);
  passed("continuous UART noise has bounded work while disconnected");

  reset();socket=connectPeer();Serial.overrun=true;fakeNow=1000;loop();
  assert(!sessionOpen && socket->stops==1 && errorSeen && Serial.tx.empty());
  fakeNow=1100;updateLed();assert(fakeLedLevel==HIGH);
  fakeNow=1200;updateLed();assert(fakeLedLevel==LOW);
  passed("actual UART overrun disconnects corrupted stream and flashes error");

  reset();socket=connectPeer();socket->room=0;Serial.rx.push_back(0xFA);
  loop();fakeNow=TCP_STALL_MS-1;loop();assert(sessionOpen);
  fakeNow=TCP_STALL_MS;loop();assert(!sessionOpen && errorSeen);
  passed("sustained TCP stall closes session after timeout");

  reset();socket=connectPeer();socket->connected=false;loop();
  assert(!sessionOpen && !errorSeen && uartToTcp.size()==0);
  auto next=connectPeer();assert(next->connected);
  next->input.push_back(0x42);loop();assert(Serial.tx==std::vector<uint8_t>{0x42});
  passed("remote close clears old pending bytes and reconnect succeeds");

  auto rejected=std::make_shared<FakeSocket>();
  server.waiting.push_back(WiFiClient(rejected));loop();
  assert(!rejected->connected && next->connected && sessionOpen);
  passed("second TCP client cannot replace active session");

  reset();WiFi.startOk=false;apReady=false;apAttemptAt=fakeNow;
  const auto starts=WiFi.starts;fakeNow=4999;loop();assert(WiFi.starts==starts);
  WiFi.startOk=true;fakeNow=5000;loop();assert(apReady && WiFi.starts==starts+1);
  passed("failed AP setup retries with bounded interval");

  reset();fakeNow=0xFFFFFF00u;socket=connectPeer();
  socket->room=0;Serial.rx.push_back(0x7F);loop();
  fakeNow=uint32_t(0xFFFFFF00u+TCP_STALL_MS-1);loop();assert(sessionOpen);
  ++fakeNow;loop();assert(!sessionOpen && errorSeen);
  passed("millis rollover preserves stall deadlines");

  std::cout<<"ALL "<<checks<<" HOST SCENARIOS PASSED\n";
}
