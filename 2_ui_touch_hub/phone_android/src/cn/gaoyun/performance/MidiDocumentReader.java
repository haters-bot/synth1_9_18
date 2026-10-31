package cn.gaoyun.performance;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

/** Read SAF content URIs through ContentResolver, never guess a disk path. */
public final class MidiDocumentReader {
    public static final int MAX_BYTES=4*1024*1024;
    private MidiDocumentReader(){}
    public static byte[] read(InputStream input) throws IOException {
        if(input==null)throw new IOException("无法读取所选文档，请确认文件已下载到手机");
        ByteArrayOutputStream output=new ByteArrayOutputStream();
        byte[] buffer=new byte[16384];int count;
        while((count=input.read(buffer))!=-1){
            if(count==0)continue;
            if(count>MAX_BYTES-output.size())throw new IOException("MIDI 文件超过4 MiB，请选取较小曲谱");
            output.write(buffer,0,count);
        }
        byte[] data=output.toByteArray();
        if(data.length<14 || data[0]!='M' || data[1]!='T' || data[2]!='h' || data[3]!='d')
            throw new IOException("所选文件不是标准 MIDI 曲谱（需要 MThd 文件头）");
        return data;
    }
}
