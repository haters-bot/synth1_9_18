import cn.gaoyun.performance.WifiNetworkSession;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import java.io.IOException;
import java.net.InetAddress;
import java.net.Socket;
import java.net.SocketAddress;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import javax.net.SocketFactory;

public final class WifiNetworkSessionTest {
    static int passed;
    static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    static InetAddress ip(String text){try{return InetAddress.getByName(text);}catch(Exception e){throw new AssertionError(e);}}
    static final class FakeSocket extends Socket {
        boolean closed,connected,noDelay,refuse;
        InetAddress local=ip("192.168.4.2");Runnable afterConnect;
        @Override public InetAddress getLocalAddress(){return local;}
        @Override public void setTcpNoDelay(boolean value){noDelay=value;}
        @Override public void connect(SocketAddress address,int timeout) throws IOException {
            if(refuse)throw new IOException("Connection refused");
            check(timeout==5000,"TCP connection timeout changed");connected=true;if(afterConnect!=null)afterConnect.run();
        }
        @Override public void close(){closed=true;}
    }
    static final class Factory extends SocketFactory {
        final FakeSocket socket=new FakeSocket();int calls;boolean deny;Runnable beforeReturn;
        @Override public Socket createSocket() throws IOException {
            calls++;if(deny)throw new IOException("Binding socket to network 144 failed: EPERM (Operation not permitted)");
            if(beforeReturn!=null)beforeReturn.run();return socket;
        }
        @Override public Socket createSocket(String h,int p){throw new AssertionError("unexpected fallback");}
        @Override public Socket createSocket(String h,int p,InetAddress l,int lp){throw new AssertionError("unexpected fallback");}
        @Override public Socket createSocket(InetAddress h,int p){throw new AssertionError("unexpected fallback");}
        @Override public Socket createSocket(InetAddress h,int p,InetAddress l,int lp){throw new AssertionError("unexpected fallback");}
    }
    static final class Manager extends ConnectivityManager {
        final Factory factory=new Factory();final Network network=new Network(144,factory);
        final CountDownLatch requestedLatch=new CountDownLatch(1);
        volatile NetworkCallback callback;int requests,releases;boolean pending,unavailable,deny,alreadyReleased;
        Network active;final NetworkCapabilities activeCapabilities=new NetworkCapabilities();
        LinkProperties properties=new LinkProperties();
        Manager(){activeCapabilities.wifi=true;properties.addresses.add(new LinkAddress(ip("192.168.4.2")));}
        @Override public Network getActiveNetwork(){return active;}
        @Override public NetworkCapabilities getNetworkCapabilities(Network n){return n==active?activeCapabilities:null;}
        @Override public LinkProperties getLinkProperties(Network n){return n==network?properties:null;}
        @Override public void requestNetwork(NetworkRequest request,NetworkCallback cb,int timeout){
            check(request.wifi && request.internetRemoved,"must request local Wi-Fi without Internet capability");
            requests++;if(deny)throw new SecurityException("CHANGE_NETWORK_STATE denied");
            callback=cb;requestedLatch.countDown();
            if(unavailable)cb.onUnavailable();else if(!pending)cb.onAvailable(network);
        }
        @Override public void unregisterNetworkCallback(NetworkCallback cb){
            check(cb==callback,"wrong network request released");releases++;
            if(alreadyReleased)throw new IllegalArgumentException("already released");
        }
    }
    interface Action {void run() throws Exception;}
    static String failure(Action action) throws Exception {
        try{action.run();throw new AssertionError("expected connection failure");}
        catch(IOException e){return e.getMessage();}
    }
    static void scenario(String name,Action action) throws Exception {action.run();passed++;System.out.println("PASS "+name);}
    public static void main(String[] args) throws Exception {
        scenario("network request held for full TCP lifetime",()->{
            Manager m=new Manager();WifiNetworkSession s=new WifiNetworkSession(m,8000);
            check(s.connect("192.168.4.1",333,5000)==m.factory.socket,"wrong socket");
            check(m.requests==1 && m.releases==0 && m.factory.socket.connected && m.factory.socket.noDelay,"network released too early");
            s.close();s.close();check(m.releases==1 && m.factory.socket.closed,"request/socket cleanup not idempotent");
        });
        scenario("binding EPERM retained and request released without fallback",()->{
            Manager m=new Manager();m.factory.deny=true;WifiNetworkSession s=new WifiNetworkSession(m,8000);
            String error=failure(()->s.connect("192.168.4.1",333,5000));
            check(error.contains("EPERM") && error.contains("网络绑定") && error.contains("144"),"lost binding diagnosis");
            check(s.describe(new IOException(error)).equals(error),"duplicated native error prefix");
            check(m.releases==1 && m.factory.calls==1,"binding failure cleanup/fallback");
        });
        scenario("network request permission denial diagnosed",()->{
            Manager m=new Manager();m.deny=true;WifiNetworkSession s=new WifiNetworkSession(m,8000);
            String error=failure(()->s.connect("192.168.4.1",333,5000));
            check(error.contains("网络申请") && error.contains("CHANGE_NETWORK_STATE"),"lost permission error");
            check(m.releases==0 && m.factory.calls==0,"denied request was used");
        });
        scenario("unavailable Wi-Fi fails before socket bind",()->{
            Manager m=new Manager();m.unavailable=true;WifiNetworkSession s=new WifiNetworkSession(m,8000);
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("系统没有提供"),"lost unavailable reason");
            check(m.releases==1 && m.factory.calls==0,"unavailable network cleanup");
        });
        scenario("TCP refusal closes socket and releases network",()->{
            Manager m=new Manager();m.factory.socket.refuse=true;WifiNetworkSession s=new WifiNetworkSession(m,8000);
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("Connection refused"),"lost TCP error");
            check(m.factory.socket.closed && m.releases==1,"refused socket leaked");
        });
        scenario("onLost closes connected socket and retains loss diagnosis",()->{
            Manager m=new Manager();WifiNetworkSession s=new WifiNetworkSession(m,8000);s.connect("192.168.4.1",333,5000);
            m.callback.onLost(m.network);check(m.factory.socket.closed,"lost network socket still open");
            check(s.describe(new IOException("Socket closed")).contains("网络已丢失"),"lost network detail");
            s.close();check(m.releases==1,"lost network request leaked");
        });
        scenario("unrelated network loss leaves current socket open",()->{
            Manager m=new Manager();WifiNetworkSession s=new WifiNetworkSession(m,8000);s.connect("192.168.4.1",333,5000);
            m.callback.onLost(new Network(999,new Factory()));check(!m.factory.socket.closed,"unrelated network closed socket");s.close();
        });
        scenario("cancel pending request wakes waiter and ignores stale callback",()->{
            Manager m=new Manager();m.pending=true;WifiNetworkSession s=new WifiNetworkSession(m,8000);
            AtomicReference<Throwable> result=new AtomicReference<>();
            Thread worker=new Thread(()->{try{s.connect("192.168.4.1",333,5000);}catch(Throwable e){result.set(e);}});worker.start();
            check(m.requestedLatch.await(1,TimeUnit.SECONDS),"request not started");s.close();worker.join(1000);
            check(!worker.isAlive() && result.get() instanceof IOException,"cancel did not finish waiter");
            m.callback.onAvailable(m.network);check(m.factory.calls==0 && m.releases==1,"late callback revived connection");
        });
        scenario("cancel while creating socket closes late socket",()->{
            Manager m=new Manager();WifiNetworkSession s=new WifiNetworkSession(m,8000);m.factory.beforeReturn=s::close;
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("取消"),"cancel reason lost");
            check(m.factory.socket.closed && m.releases==1,"late-created socket leaked");
        });
        scenario("already released Android timeout request is safe to close",()->{
            Manager m=new Manager();m.unavailable=true;m.alreadyReleased=true;WifiNetworkSession s=new WifiNetworkSession(m,8000);
            failure(()->s.connect("192.168.4.1",333,5000));s.close();check(m.releases==1,"duplicate unregister");
        });
        scenario("separate reconnect sessions do not close one another",()->{
            Manager old=new Manager(),next=new Manager();WifiNetworkSession a=new WifiNetworkSession(old,8000),b=new WifiNetworkSession(next,8000);
            a.connect("192.168.4.1",333,5000);b.connect("192.168.4.1",333,5000);a.close();old.callback.onLost(old.network);
            check(!next.factory.socket.closed && next.releases==0,"stale session closed new connection");b.close();
        });
        scenario("default Wi-Fi normal socket avoids unnecessary network bind",()->{
            Manager m=new Manager();m.active=m.network;m.factory.deny=true;Factory ordinary=new Factory();StringBuilder log=new StringBuilder();
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->log.append(message));
            check(s.connect("192.168.4.1",333,5000)==ordinary.socket,"ordinary Wi-Fi socket not selected");
            check(m.factory.calls==0 && ordinary.calls==1,"unnecessary per-network bind attempted");
            check(log.toString().contains("系统默认Wi-Fi TCP") && log.toString().contains("192.168.4.2"),"route diagnosis missing");
            s.close();check(ordinary.socket.closed && m.releases==1,"ordinary socket cleanup failed");
        });
        scenario("cellular default never uses ordinary socket",()->{
            Manager m=new Manager();m.active=new Network(200,new Factory());m.activeCapabilities.wifi=false;Factory ordinary=new Factory();
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});s.connect("192.168.4.1",333,5000);
            check(ordinary.calls==0 && m.factory.calls==1,"ordinary socket could use cellular");s.close();
        });
        scenario("another Wi-Fi default never uses ordinary socket",()->{
            Manager m=new Manager();m.active=new Network(200,new Factory());Factory ordinary=new Factory();
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});s.connect("192.168.4.1",333,5000);
            check(ordinary.calls==0 && m.factory.calls==1,"ordinary socket could use another Wi-Fi");s.close();
        });
        scenario("VPN-capable default never uses ordinary socket",()->{
            Manager m=new Manager();m.active=m.network;m.activeCapabilities.vpn=true;Factory ordinary=new Factory();
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});s.connect("192.168.4.1",333,5000);
            check(ordinary.calls==0 && m.factory.calls==1,"VPN default was treated as direct Wi-Fi");s.close();
        });
        scenario("wrong local address rejected before protocol traffic",()->{
            Manager m=new Manager();m.active=m.network;Factory ordinary=new Factory();ordinary.socket.local=ip("10.0.0.2");
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("TCP本地地址"),"source address not verified");
            check(ordinary.socket.closed && m.releases==1,"wrong-route socket leaked");
        });
        scenario("default network change during connect cancels connection",()->{
            Manager m=new Manager();m.active=m.network;Factory ordinary=new Factory();ordinary.socket.afterConnect=()->m.active=null;
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("默认网络已变化"),"route change ignored");
            check(ordinary.socket.closed && m.releases==1,"changed-route socket leaked");
        });
        scenario("missing Wi-Fi link properties does not claim route verified",()->{
            Manager m=new Manager();m.active=m.network;m.properties=null;Factory ordinary=new Factory();
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("TCP本地地址"),"missing link properties accepted");
            check(ordinary.socket.closed && m.releases==1,"unverified-route socket leaked");
        });
        scenario("ordinary socket permission denial remains explicit without retrying another route",()->{
            Manager m=new Manager();m.active=m.network;Factory ordinary=new Factory();ordinary.deny=true;
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("EPERM"),"ordinary socket permission denial hidden");
            check(ordinary.calls==1 && m.factory.calls==0 && m.releases==1,"permission denial caused another route attempt");
        });
        scenario("ordinary TCP refusal closes socket and releases network",()->{
            Manager m=new Manager();m.active=m.network;Factory ordinary=new Factory();ordinary.socket.refuse=true;
            WifiNetworkSession s=new WifiNetworkSession(m,8000,ordinary,message->{});
            check(failure(()->s.connect("192.168.4.1",333,5000)).contains("Connection refused"),"TCP refusal lost");
            check(ordinary.socket.closed && m.releases==1 && m.factory.calls==0,"TCP failure retried another route");
        });
        System.out.println("PASS: "+passed+" production WifiNetworkSession scenarios; Android callbacks are modeled, real-device verification pending");
    }
}
