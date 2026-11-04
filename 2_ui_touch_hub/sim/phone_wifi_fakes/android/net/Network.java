package android.net;
import javax.net.SocketFactory;
public final class Network {
    private final int id;
    private final SocketFactory factory;
    public Network(int id,SocketFactory factory){this.id=id;this.factory=factory;}
    public SocketFactory getSocketFactory(){return factory;}
    @Override public String toString(){return Integer.toString(id);}
}
