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
        File durable=new File(dir,"durable");durable.mkdir();
        for(int ch=1;ch<=2;ch++) {
            final int channels=ch,frames=2053;String identity="module-A/token-"+ch+"/generation-3/8k";
            byte[] pcm=new byte[frames*ch*2];new Random(79+ch).nextBytes(pcm);
            WavDownloadStore first=new WavDownloadStore();
            WavDownloadStore.Entry e=first.open(durable,identity,"take.wav",frames,ch);
            first.append(Arrays.copyOfRange(pcm,0,1024*ch*2));first.close();
            if(WavDownloadStore.inspect(durable,e.key).receivedFrames()!=1024)throw new AssertionError("missing committed offset");
            rejected(()->WavDownloadStore.completeFile(durable,e.key));
            // Simulate death after PCM fsync but BEFORE metadata commit. Resume
            // must overwrite the uncommitted suffix, with no duplication.
            try(RandomAccessFile f=new RandomAccessFile(new File(durable,e.key+".wav"),"rw")) {
                f.seek(f.length());f.write(new byte[37*ch*2]);f.getFD().sync();
            }
            WavDownloadStore reopened=new WavDownloadStore();
            WavDownloadStore.Entry restored=reopened.open(durable,identity,"take.wav",frames,ch);
            if(restored.receivedFrames()!=1024)throw new AssertionError("trusted uncommitted bytes");
            reopened.append(Arrays.copyOfRange(pcm,1024*ch*2,2048*ch*2));
            reopened.append(Arrays.copyOfRange(pcm,2048*ch*2,pcm.length));reopened.close();
            byte[] wave=Files.readAllBytes(WavDownloadStore.completeFile(durable,e.key).toPath());
            if(wave.length!=44+pcm.length || !Arrays.equals(pcm,Arrays.copyOfRange(wave,44,wave.length)))
                throw new AssertionError("resumed mono/stereo WAV bytes differ");
            WavDownloadStore again=new WavDownloadStore();
            if(!again.open(durable,identity,"take.wav",frames,ch).complete())throw new AssertionError("completed cache not reusable");
            again.close();rejected(()->new WavDownloadStore().open(durable,identity,"take.wav",frames+1,channels));
            if(WavDownloadStore.keyFor(identity).equals(WavDownloadStore.keyFor(identity+"different-token")))throw new AssertionError("identity collision");
        }
        if(WavDownloadStore.list(durable).size()!=2)throw new AssertionError("cache list missing recordings");
        rejected(()->WavDownloadStore.inspect(durable,"../../other"));
        File badDir=new File(dir,"corrupt");badDir.mkdir();
        String badKey=WavDownloadStore.keyFor("corrupt-test");
        Files.write(new File(badDir,badKey+".properties").toPath(),"frames=bad".getBytes("UTF-8"));
        rejected(()->WavDownloadStore.inspect(badDir,badKey));
        rejected(()->WavDownloadStore.list(badDir));
        if(!new File(badDir,badKey+".properties").exists())throw new AssertionError("corrupt evidence deleted");
        File orphanDir=new File(dir,"orphan");orphanDir.mkdir();
        File orphan=new File(orphanDir,WavDownloadStore.keyFor("orphan")+".wav");Files.write(orphan.toPath(),new byte[]{7,8,9});
        rejected(()->new WavDownloadStore().open(orphanDir,"orphan","take.wav",10,1));
        if(!Arrays.equals(Files.readAllBytes(orphan.toPath()),new byte[]{7,8,9}))throw new AssertionError("orphan overwritten");
        System.out.println("PASS: native mono/stereo WAV bytes, durable restart/resume, crash suffix rollback, offline complete cache, identity/length/path/corruption/orphan guards; all evidence retained, no deletion");
    }
}
