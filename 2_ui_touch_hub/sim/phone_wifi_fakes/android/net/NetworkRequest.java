package android.net;
public final class NetworkRequest {
    public boolean wifi,internetRemoved;
    public static final class Builder {
        private final NetworkRequest request=new NetworkRequest();
        public Builder addTransportType(int transport){request.wifi=transport==NetworkCapabilities.TRANSPORT_WIFI;return this;}
        public Builder removeCapability(int capability){request.internetRemoved=capability==NetworkCapabilities.NET_CAPABILITY_INTERNET;return this;}
        public NetworkRequest build(){return request;}
    }
}
