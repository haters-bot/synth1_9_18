package android.net;
public class ConnectivityManager {
    public static class NetworkCallback {
        public void onAvailable(Network network){}
        public void onUnavailable(){}
        public void onLost(Network network){}
    }
    public void requestNetwork(NetworkRequest request,NetworkCallback callback,int timeout){throw new UnsupportedOperationException();}
    public Network getActiveNetwork(){return null;}
    public NetworkCapabilities getNetworkCapabilities(Network network){return null;}
    public LinkProperties getLinkProperties(Network network){return null;}
    public void unregisterNetworkCallback(NetworkCallback callback){throw new UnsupportedOperationException();}
}
