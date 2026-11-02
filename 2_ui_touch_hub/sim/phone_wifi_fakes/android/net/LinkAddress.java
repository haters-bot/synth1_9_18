package android.net;
import java.net.InetAddress;
public final class LinkAddress {
    private final InetAddress address;
    public LinkAddress(InetAddress address){this.address=address;}
    public InetAddress getAddress(){return address;}
}
