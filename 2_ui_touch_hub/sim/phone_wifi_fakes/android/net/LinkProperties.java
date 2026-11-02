package android.net;
import java.util.ArrayList;
import java.util.List;
public final class LinkProperties {
    public final List<LinkAddress> addresses=new ArrayList<>();
    public List<LinkAddress> getLinkAddresses(){return addresses;}
}
