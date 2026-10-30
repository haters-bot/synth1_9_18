package cn.gaoyun.performance;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Used on the file executor. An incomplete transfer is never exportable. */
public final class WavDownloadStore {
    private File file;
    private FileOutputStream output;
    private long expected, received;
    private int frameBytes;

    public void begin(File directory,int frames,int channels) throws IOException {
        if(output!=null || frames<=0 || frames>22369621 || (channels!=1 && channels!=2))
            throw new IOException("保存任务或帧数无效");
        file=File.createTempFile("fpga_take_",".wav",directory);
        expected=(long)frames*channels*2;received=0;frameBytes=channels*2;
        output=new FileOutputStream(file);
        ByteBuffer h=ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        h.put(new byte[]{'R','I','F','F'}).putInt((int)(36+expected)).put(new byte[]{'W','A','V','E','f','m','t',' '});
        h.putInt(16).putShort((short)1).putShort((short)channels).putInt(8000).putInt(8000*frameBytes);
        h.putShort((short)frameBytes).putShort((short)16).put(new byte[]{'d','a','t','a'}).putInt((int)expected);
        output.write(h.array());
    }
    public void append(byte[] data) throws IOException {
        if(output==null || data.length==0 || data.length>4096 || data.length%frameBytes!=0 || received+data.length>expected)
            throw new IOException("WAV 写入状态／长度无效");
        output.write(data);received+=data.length;
    }
    public File finish() throws IOException {
        if(output==null || received!=expected)throw new IOException("WAV 数据尚未完整接收，不导出残缺文件");
        output.flush();close();
        if(file.length()!=44+expected)throw new IOException("录音缓存长度不符");
        return file;
    }
    public void close() throws IOException {
        if(output!=null){FileOutputStream old=output;output=null;old.close();}
    }
}
