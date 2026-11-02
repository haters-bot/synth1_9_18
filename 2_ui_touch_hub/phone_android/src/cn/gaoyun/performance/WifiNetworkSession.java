package cn.gaoyun.performance;

import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;
import javax.net.SocketFactory;

/** Own the requested Wi-Fi network for the entire socket lifetime. */
public final class WifiNetworkSession implements AutoCloseable {
    private final ConnectivityManager manager;
    private final int networkTimeoutMs;
    private final SocketFactory defaultSockets;
    private final Consumer<String> trace;
    private final CountDownLatch ready=new CountDownLatch(1);
    private Network network;
    private Socket socket;
    private IOException networkFailure;
    private boolean requested,started,closed;
    private String phase="Wi-Fi网络申请";

    private final ConnectivityManager.NetworkCallback callback=new ConnectivityManager.NetworkCallback(){
        @Override public void onAvailable(Network available){
            synchronized(WifiNetworkSession.this){
                if(closed || network!=null || networkFailure!=null)return;
                network=available;ready.countDown();
            }
        }
        @Override public void onUnavailable(){
            fail(new IOException("系统没有提供可用的Wi-Fi网络；请先连接ESP热点并选择保持连接"));
        }
        @Override public void onLost(Network lost){
            synchronized(WifiNetworkSession.this){
                if(closed || !lost.equals(network))return;
            }
            fail(new IOException("系统报告ESP所用Wi-Fi网络已丢失（network "+lost+"）"));
        }
    };

    public WifiNetworkSession(ConnectivityManager manager,int networkTimeoutMs){
        this(manager,networkTimeoutMs,SocketFactory.getDefault(),message->{});
    }

    public WifiNetworkSession(ConnectivityManager manager,int networkTimeoutMs,Consumer<String> trace){
        this(manager,networkTimeoutMs,SocketFactory.getDefault(),trace);
    }

    public WifiNetworkSession(ConnectivityManager manager,int networkTimeoutMs,SocketFactory defaultSockets,Consumer<String> trace){
        this.manager=manager;this.networkTimeoutMs=networkTimeoutMs;
        this.defaultSockets=defaultSockets;this.trace=trace;
    }

    private boolean isDefaultWifi(Network selected){
        Network active=manager.getActiveNetwork();
        NetworkCapabilities capabilities=active==null?null:manager.getNetworkCapabilities(active);
        return selected.equals(active) && capabilities!=null &&
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
    }

    private void verifyDefaultRoute(Network selected,Socket candidate) throws IOException {
        if(!isDefaultWifi(selected))throw new IOException("连接期间系统默认网络已变化；请保持ESP Wi-Fi连接后重试");
        LinkProperties properties=manager.getLinkProperties(selected);
        if(properties!=null)for(LinkAddress address:properties.getLinkAddresses())
            if(address.getAddress().equals(candidate.getLocalAddress()))return;
        throw new IOException("TCP本地地址未能确认为ESP Wi-Fi地址；已停止连接，请保持ESP热点连接后重试");
    }

    private void trace(String message){
        try {trace.accept(message);}catch(RuntimeException ignored){}
    }

    private synchronized void fail(IOException reason){
        if(closed || networkFailure!=null)return;
        networkFailure=reason;ready.countDown();closeSocket(socket);
    }

    private synchronized void checkOpen() throws IOException {
        if(networkFailure!=null)throw networkFailure;
        if(closed)throw new IOException("Wi-Fi连接已取消");
    }

    public Socket connect(String host,int port,int connectTimeoutMs) throws IOException {
        try {
            synchronized(this){
                checkOpen();
                if(started)throw new IOException("此Wi-Fi会话已经发起过连接");
                started=true;
                NetworkRequest request=new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    // The ESP hotspot serves only the local TCP endpoint.
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build();
                requested=true;
                try {manager.requestNetwork(request,callback,networkTimeoutMs);}
                catch(RuntimeException e){requested=false;throw e;}
            }
            if(!ready.await(networkTimeoutMs+1000L,TimeUnit.MILLISECONDS))
                throw new IOException("等待系统提供ESP Wi-Fi网络超时");
            final Network selected;
            synchronized(this){checkOpen();selected=network;}
            // A normal socket needs no per-network bind when this exact Wi-Fi
            // is already the app's default. Android still applies its policies.
            final boolean useDefault=isDefaultWifi(selected);
            final String method=useDefault?"系统默认Wi-Fi TCP":"显式Wi-Fi网络绑定";
            trace("Wi-Fi诊断：请求network="+selected+"，系统默认network="+manager.getActiveNetwork()+"，方式="+method);
            synchronized(this){phase=method+"（network "+selected+"）";}
            Socket candidate=useDefault?defaultSockets.createSocket():selected.getSocketFactory().createSocket();
            synchronized(this){
                try {checkOpen();socket=candidate;}
                catch(IOException e){closeSocket(candidate);throw e;}
                phase="Wi-Fi TCP连接（"+host+":"+port+"，network "+selected+"）";
            }
            candidate.setTcpNoDelay(true);
            candidate.connect(new InetSocketAddress(host,port),connectTimeoutMs);
            if(useDefault)verifyDefaultRoute(selected,candidate);
            synchronized(this){checkOpen();phase="Wi-Fi TCP收发（network "+selected+"）";}
            trace("Wi-Fi TCP已连接："+method+"，本地="+candidate.getLocalAddress().getHostAddress()+"，目标="+host+":"+port);
            return candidate;
        } catch(InterruptedException e){
            Thread.currentThread().interrupt();String message=describe(e);close();throw new IOException(message,e);
        } catch(IOException | RuntimeException e){
            String message=describe(e);close();throw new IOException(message,e);
        }
    }

    public synchronized String describe(Exception error){
        if(networkFailure!=null)return networkFailure.getMessage();
        String detail=error.getMessage()==null?error.toString():error.getMessage();
        String prefix=phase+"失败：";
        String message=detail.startsWith(prefix)?detail:prefix+detail;
        if(detail.contains("EPERM") && !message.contains("请先确认"))
            message+="；请先确认本App已允许使用Wi-Fi。若默认网络仍为移动网络，请暂时关闭移动数据/自动切换网络，保持ESP热点后重试";
        return message;
    }

    private static void closeSocket(Socket value){
        if(value!=null)try {value.close();}catch(IOException ignored){}
    }

    @Override public synchronized void close(){
        if(closed)return;
        closed=true;ready.countDown();closeSocket(socket);
        if(requested){
            requested=false;
            // A timed-out request may already have been released by Android.
            try {manager.unregisterNetworkCallback(callback);}catch(IllegalArgumentException ignored){}
        }
    }
}
