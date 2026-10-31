package cn.gaoyun.performance;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.FileInputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

/** Used on the file executor. An incomplete transfer is never exportable. */
public final class WavDownloadStore {
    private File file;
    private RandomAccessFile output;
    private long expected, received;
    private int frameBytes;
    private File metadata;
    private Entry entry;

    public static final class Entry {
        public String key,identity,name;
        public int frames,channels;
        public long receivedBytes;
        public int receivedFrames(){return (int)(receivedBytes/(channels*2));}
        public boolean complete(){return receivedFrames()==frames;}
    }

    public static String keyFor(String identity) throws IOException {
        if(identity==null || identity.isEmpty() || identity.length()>2048)throw new IOException("缓存身份无效");
        try {
            byte[] hash=MessageDigest.getInstance("SHA-256").digest(identity.getBytes("UTF-8"));
            StringBuilder text=new StringBuilder();for(byte b:hash)text.append(String.format("%02x",b&255));return text.toString();
        }catch(Exception e){throw new IOException(e);}
    }
    private static File path(File directory,String key,String extension) throws IOException {
        if(key==null || !key.matches("[0-9a-f]{64}"))throw new IOException("缓存编号无效");
        File f=new File(directory,key+extension);
        if(!f.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile()))throw new IOException("缓存路径无效");
        return f;
    }
    public static Entry inspect(File directory,String key) throws IOException {
        File meta=path(directory,key,".properties"),pcm=path(directory,key,".wav");
        Properties p=new Properties();try(FileInputStream input=new FileInputStream(meta)){p.load(input);}
        try {
            Entry e=new Entry();e.key=key;e.identity=p.getProperty("identity");e.name=p.getProperty("name");
            e.frames=Integer.parseInt(p.getProperty("frames"));e.channels=Integer.parseInt(p.getProperty("channels"));
            e.receivedBytes=Long.parseLong(p.getProperty("received"));
            long size=(long)e.frames*e.channels*2;
            if(!keyFor(e.identity).equals(key) || e.name==null || e.frames<=0 || e.frames>22369621 ||
               (e.channels!=1 && e.channels!=2) || e.receivedBytes<0 || e.receivedBytes>size ||
               e.receivedBytes%(e.channels*2)!=0 || !pcm.isFile() || pcm.length()<44+e.receivedBytes || pcm.length()>44+size)
                throw new IOException("录音缓存／进度不一致，保留原文件");
            try(RandomAccessFile input=new RandomAccessFile(pcm,"r")){
                byte[] header=new byte[44];input.readFully(header);
                if(!java.util.Arrays.equals(header,header(e.frames,e.channels)))throw new IOException("缓存WAV头不符");
            }
            return e;
        }catch(RuntimeException e){throw new IOException("录音缓存元数据损坏，保留原文件",e);}
    }
    public static List<Entry> list(File directory) throws IOException {
        List<Entry> entries=new ArrayList<>();File[] files=directory.listFiles((dir,name)->name.matches("[0-9a-f]{64}\\.properties"));
        if(files==null)return entries;
        for(File f:files)entries.add(inspect(directory,f.getName().substring(0,64)));
        return entries;
    }
    private void checkpoint() throws IOException {
        if(metadata==null)return;
        Properties p=new Properties();p.setProperty("identity",entry.identity);p.setProperty("name",entry.name);
        p.setProperty("frames",Integer.toString(entry.frames));p.setProperty("channels",Integer.toString(entry.channels));
        p.setProperty("received",Long.toString(received));
        File next=new File(metadata.getPath()+".pending");
        try(FileOutputStream stream=new FileOutputStream(next)){p.store(stream,"FPGA durable download checkpoint");stream.getFD().sync();}
        Files.move(next.toPath(),metadata.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        entry.receivedBytes=received;
    }
    public Entry open(File directory,String identity,String name,int frames,int channels) throws IOException {
        if(output!=null)throw new IOException("已有缓存写入任务");
        if(!directory.isDirectory() && !directory.mkdirs())throw new IOException("无法创建应用录音目录");
        if(frames<=0 || frames>22369621 || (channels!=1 && channels!=2) || name==null || name.length()>200)throw new IOException("录音参数无效");
        String key=keyFor(identity);file=path(directory,key,".wav");metadata=path(directory,key,".properties");
        expected=(long)frames*channels*2;frameBytes=channels*2;
        if(metadata.exists()) {
            entry=inspect(directory,key);
            if(entry.frames!=frames || entry.channels!=channels || !identity.equals(entry.identity))throw new IOException("缓存属于其他录音");
            received=entry.receivedBytes;
        } else {
            if(file.exists())throw new IOException("发现未登记的缓存，保留原文件，不覆盖");
            entry=new Entry();entry.key=key;entry.identity=identity;entry.name=name;entry.frames=frames;entry.channels=channels;received=0;
        }
        if(received<expected && directory.getUsableSpace()<expected-received+1048576)throw new IOException("手机可用存储不足");
        output=new RandomAccessFile(file,"rw");
        if(file.length()==0){output.write(header(frames,channels));output.getFD().sync();}
        // Only committed bytes are trusted. A crash may leave an uncommitted
        // suffix; re-download over that suffix without discarding the cache.
        try{output.seek(44+received);checkpoint();return entry;}
        catch(IOException e){close();throw e;}
    }
    public static File completeFile(File directory,String key) throws IOException {
        Entry e=inspect(directory,key);File result=path(directory,key,".wav");
        if(!e.complete() || result.length()!=44+(long)e.frames*e.channels*2)throw new IOException("录音缓存尚未完整，不导出");
        return result;
    }
    // Called ONLY after the user confirms the explicit delete action.
    public static void remove(File directory,String key) throws IOException {
        inspect(directory,key);
        for(String ext:new String[]{".wav",".properties",".properties.pending"}) {
            File f=path(directory,key,ext);if(f.exists() && !f.delete())throw new IOException("无法删除所选缓存");
        }
    }
    public String activeKey(){return entry==null?null:entry.key;}
    public int receivedFrames(){return frameBytes==0?0:(int)(received/frameBytes);}

    public void begin(File directory,int frames,int channels) throws IOException {
        if(output!=null || frames<=0 || frames>22369621 || (channels!=1 && channels!=2))
            throw new IOException("保存任务或帧数无效");
        file=File.createTempFile("fpga_take_",".wav",directory);
        metadata=null;entry=null;
        expected=(long)frames*channels*2;received=0;frameBytes=channels*2;
        output=new RandomAccessFile(file,"rw");output.write(header(frames,channels));
    }
    private static byte[] header(int frames,int channels) {
        long expected=(long)frames*channels*2;int frameBytes=channels*2;
        ByteBuffer h=ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        h.put(new byte[]{'R','I','F','F'}).putInt((int)(36+expected)).put(new byte[]{'W','A','V','E','f','m','t',' '});
        h.putInt(16).putShort((short)1).putShort((short)channels).putInt(8000).putInt(8000*frameBytes);
        h.putShort((short)frameBytes).putShort((short)16).put(new byte[]{'d','a','t','a'}).putInt((int)expected);
        return h.array();
    }
    public void append(byte[] data) throws IOException {
        if(output==null || data.length==0 || data.length>4096 || data.length%frameBytes!=0 || received+data.length>expected)
            throw new IOException("WAV 写入状态／长度无效");
        output.write(data);output.getFD().sync();received+=data.length;checkpoint();
    }
    public File finish() throws IOException {
        if(output==null || received!=expected)throw new IOException("WAV 数据尚未完整接收，不导出残缺文件");
        output.getFD().sync();close();
        if(file.length()!=44+expected)throw new IOException("录音缓存长度不符");
        return file;
    }
    public void close() throws IOException {
        if(output!=null){RandomAccessFile old=output;output=null;old.close();}
    }
}
