package android.net;
public final class NetworkCapabilities {
    public static final int TRANSPORT_WIFI=1,TRANSPORT_VPN=4,NET_CAPABILITY_INTERNET=12;
    public boolean wifi,vpn;
    public boolean hasTransport(int transport){return transport==TRANSPORT_WIFI?wifi:transport==TRANSPORT_VPN && vpn;}
}
