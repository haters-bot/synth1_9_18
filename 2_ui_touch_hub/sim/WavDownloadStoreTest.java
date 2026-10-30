import cn.gaoyun.performance.WavDownloadStore;
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;

public class WavDownloadStoreTest {
    interface Work {void run() throws Exception;}
    static void rejected(Work work) throws Exception {
        try {work.run();}catch(IOException expected){return;}
        throw new AssertionError("incomplete/invalid transfer accepted");
    }
    public static void main(String[] args) throws Exception {
        File dir=new File(args[0]);WavDownloadStore store=new WavDownloadStore();
        rejected(()->store.begin(dir,0,1));
        for(int channels=1;channels<=2;channels++) {
            final int ch=channels;int frames=1029;
            byte[] pcm=new byte[frames*ch*2];new Random(ch).nextBytes(pcm);
            store.begin(dir,frames,ch);rejected(()->store.finish());
            rejected(()->store.append(new byte[1]));
            int first=1024*ch*2;store.append(Arrays.copyOfRange(pcm,0,first));
            rejected(()->store.finish());
            store.append(Arrays.copyOfRange(pcm,first,pcm.length));
            rejected(()->store.append(new byte[ch*2]));
            File complete=store.finish();byte[] wave=Files.readAllBytes(complete.toPath());
            ByteBuffer header=ByteBuffer.wrap(wave).order(ByteOrder.LITTLE_ENDIAN);
            if(wave.length!=44+pcm.length || header.getInt(40)!=pcm.length || header.getShort(22)!=ch ||
               header.getInt(24)!=8000 || !Arrays.equals(pcm,Arrays.copyOfRange(wave,44,wave.length)))
                throw new AssertionError("actual WAV bytes differ");
            rejected(()->store.append(new byte[ch*2]));
        }
        store.begin(dir,137360,1);store.close();rejected(()->store.finish());
        store.begin(dir,1,1);store.append(new byte[]{12,34});store.finish();
        System.out.println("PASS: production native WAV cache, exact mono/stereo headers/PCM, missing/partial/overflow rejected, cancel/restart; evidence retained");
    }
}
