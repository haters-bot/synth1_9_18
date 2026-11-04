#pragma once
#include "Arduino.h"
#include <memory>
#include <string>

static constexpr int WIFI_NONE_SLEEP=0, WIFI_AP=2;
struct IPAddress {
  uint8_t bytes[4];
  IPAddress(int a,int b,int c,int d):bytes{uint8_t(a),uint8_t(b),uint8_t(c),uint8_t(d)}{}
};
struct FakeSocket {
  bool connected=true;
  unsigned stops=0;
  size_t room=65536, writeLimit=65536;
  std::deque<uint8_t> input;
  std::vector<uint8_t> output;
};
class WiFiClient {
 public:
  std::shared_ptr<FakeSocket> state;
  WiFiClient()=default;
  explicit WiFiClient(std::shared_ptr<FakeSocket> value):state(value){}
  explicit operator bool() const { return state && state->connected; }
  bool connected() const { return state && state->connected; }
  void stop() { if(state){state->connected=false;++state->stops;} }
  void setNoDelay(bool value) { (void)value; }
  int available() { return state ? int(state->input.size()) : 0; }
  size_t availableForWrite() { return connected() ? state->room : 0; }
  int read(uint8_t* target,size_t count) {
    if(!state)return -1;
    count=std::min(count,state->input.size());
    for(size_t i=0;i<count;++i){target[i]=state->input.front();state->input.pop_front();}
    return int(count);
  }
  size_t write(const uint8_t* data,size_t count) {
    if(!connected())return 0;
    count=std::min(count,std::min(state->room,state->writeLimit));
    state->output.insert(state->output.end(),data,data+count);return count;
  }
};
class WiFiServer {
 public:
  std::deque<WiFiClient> waiting;
  unsigned begins=0;
  explicit WiFiServer(unsigned port) { (void)port; }
  void begin() { ++begins; }
  void setNoDelay(bool value) { (void)value; }
  bool hasClient() { return !waiting.empty(); }
  WiFiClient accept() {
    if(waiting.empty())return WiFiClient();
    auto value=waiting.front();waiting.pop_front();return value;
  }
};
class FakeWiFi {
 public:
  unsigned stations=0, starts=0;
  bool configOk=true, startOk=true;
  std::string ssid;
  void persistent(bool value) { (void)value; }
  void setSleepMode(int value) { (void)value; }
  void mode(int value) { (void)value; }
  bool softAPConfig(IPAddress ip,IPAddress gateway,IPAddress mask) {
    (void)ip;(void)gateway;(void)mask;return configOk;
  }
  bool softAP(const char* name,const char* pass,int channel,bool hidden,int clients) {
    (void)pass;(void)channel;(void)hidden;(void)clients;
    ssid=name;++starts;return startOk;
  }
  unsigned softAPgetStationNum() { return stations; }
};
static FakeWiFi WiFi;
