import cn.gaoyun.performance.MidiDocumentReader;
import java.io.*;
import java.util.Arrays;
public final class MidiDocumentReaderTest {
    interface Test {void run() throws Exception;}
    static void rejects(Test test) throws Exception {try{test.run();}catch(IOException expected){return;}throw new AssertionError("accepted invalid document");}
    public static void main(String[] args) throws Exception {
        byte[] midi=new byte[31];midi[0]='M';midi[1]='T';midi[2]='h';midi[3]='d';
        InputStream fragmented=new ByteArrayInputStream(midi){public synchronized int read(byte[] b,int o,int n){return super.read(b,o,Math.min(3,n));}};
        if(!Arrays.equals(midi,MidiDocumentReader.read(fragmented)))throw new AssertionError("short read corrupted file");
        rejects(()->MidiDocumentReader.read(null));rejects(()->MidiDocumentReader.read(new ByteArrayInputStream(new byte[0])));
        rejects(()->MidiDocumentReader.read(new ByteArrayInputStream(new byte[14])));
        rejects(()->MidiDocumentReader.read(new ByteArrayInputStream(new byte[MidiDocumentReader.MAX_BYTES+1])));
        rejects(()->MidiDocumentReader.read(new InputStream(){public int read() throws IOException {throw new IOException("provider unavailable");}}));
        System.out.println("PASS: native document reader: fragmented reads, null/empty/invalid/oversize/provider failure");
    }
}
