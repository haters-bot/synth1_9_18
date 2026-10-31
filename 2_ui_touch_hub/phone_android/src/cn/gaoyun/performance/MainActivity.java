package cn.gaoyun.performance;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothSocket;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.database.Cursor;
import android.provider.OpenableColumns;
import android.util.Base64;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;
import java.io.InputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Local assets only. No microphone, location, Internet or broad-storage access. */
public final class MainActivity extends Activity {
    private static final int CONNECT_PERMISSION=10, OPEN_MIDI=11, SAVE_WAV=12, ENABLE_BT=13;
    private static final String HOME="file:///android_asset/index.html";
    private static final UUID SPP=UUID.fromString("00001101-0000-1000-8000-00805f9b34fb");
    private WebView web;
    private volatile BluetoothSocket socket;
    private volatile OutputStream bluetoothOut;
    private volatile boolean destroyed;
    private final ExecutorService writes=Executors.newSingleThreadExecutor();
    private final ExecutorService files=Executors.newSingleThreadExecutor();
    private ValueCallback<Uri[]> fileChoice;
    private boolean nativeMidiChoice;
    private final WavDownloadStore wavStore=new WavDownloadStore();
    private volatile boolean saveDialog,saveCopying;
    private File wavCache;
    private String saveName;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        web=new WebView(this);setContentView(web);
        web.setBackgroundColor(0xff111622);
        WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true);settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !HOME.equals(request.getUrl().toString());
            }
        });
        web.setWebChromeClient(new WebChromeClient(){
            @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params) {
                if(fileChoice!=null)fileChoice.onReceiveValue(null);
                fileChoice=callback;
                Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
                try{startActivityForResult(intent,OPEN_MIDI);}catch(Exception e){callback.onReceiveValue(null);fileChoice=null;error(e);}
                return true;
            }
        });
        web.addJavascriptInterface(new PhoneBridge(),"PhoneNative");web.loadUrl(HOME);
        // Avoid system bars covering the controls when targeting Android 15.
        web.setOnApplyWindowInsetsListener((view,insets)->{
            view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;
        });
    }
    private void js(String script) {
        if(destroyed)return;
        runOnUiThread(()->{if(!destroyed && HOME.equals(web.getUrl()))web.evaluateJavascript(script,null);});
    }
    private void event(String name,String value) {js("window."+name+" && window."+name+"("+JSONObject.quote(value)+");");}
    private void error(Exception error) {event("onNativeError",error.getMessage()==null?error.toString():error.getMessage());}
    private void chooseMidi() {
        if(nativeMidiChoice){event("onNativeMidiError","文件选择正在进行，请稍候");return;}
        nativeMidiChoice=true;
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
        try{startActivityForResult(intent,OPEN_MIDI);}
        catch(Exception e){nativeMidiChoice=false;event("onNativeMidiError",e.toString());}
    }
    private void readMidi(final Uri uri) {
        files.execute(()->{
            try {
                String name="selected.mid";
                try(Cursor cursor=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)) {
                    if(cursor!=null && cursor.moveToFirst() && !cursor.isNull(0))name=cursor.getString(0);
                }
                final byte[] bytes;
                try(InputStream input=getContentResolver().openInputStream(uri)) {
                    bytes=MidiDocumentReader.read(input);
                }
                js("window.onNativeMidiSelected && window.onNativeMidiSelected("+JSONObject.quote(name)+","+
                    JSONObject.quote(Base64.encodeToString(bytes,Base64.NO_WRAP))+");");
            }catch(Exception e){event("onNativeMidiError",e.getMessage()==null?e.toString():e.getMessage());}
            finally{runOnUiThread(()->nativeMidiChoice=false);}
        });
    }
    private BluetoothAdapter adapter() {
        BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);
        return manager==null?null:manager.getAdapter();
    }
    private void chooseDevice() {
        if(Build.VERSION.SDK_INT>=31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT},CONNECT_PERMISSION);return;
        }
        try {
            BluetoothAdapter bt=adapter();if(bt==null)throw new Exception("此手机没有可用蓝牙适配器");
            if(!bt.isEnabled()){startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),ENABLE_BT);return;}
            Set<BluetoothDevice> paired=bt.getBondedDevices();
            ArrayList<BluetoothDevice> devices=new ArrayList<>(paired);
            if(devices.isEmpty())throw new Exception("请先在系统蓝牙设置配对模块；HC-07手册默认 PIN 为1234，实际型号可能不同");
            String[] labels=new String[devices.size()];
            for(int i=0;i<labels.length;i++)labels[i]=devices.get(i).getName()+"\n"+devices.get(i).getAddress();
            new AlertDialog.Builder(this).setTitle("选择已配对的串口模块").setItems(labels,(dialog,which)->connect(devices.get(which))).setNegativeButton("取消",null).show();
        }catch(Exception e){error(e);}
    }
    private void disconnect() {
        BluetoothSocket old=socket;socket=null;bluetoothOut=null;
        if(old!=null)try{old.close();}catch(Exception ignored){}
    }
    private void connect(BluetoothDevice device) {
        disconnect();
        new Thread(()->{
            BluetoothSocket current=null;
            try {
                current=device.createRfcommSocketToServiceRecord(SPP);socket=current;
                // Paired-device connection only: no discovery and no SCAN/location permission.
                current.connect();if(socket!=current){current.close();return;}
                bluetoothOut=current.getOutputStream();InputStream input=current.getInputStream();
                event("onNativeConnected",device.getAddress());
                byte[] buffer=new byte[1024];int count;
                while(socket==current && (count=input.read(buffer))!=-1)
                    event("onNativeBytes",Base64.encodeToString(buffer,0,count,Base64.NO_WRAP));
                if(socket==current)throw new Exception("蓝牙串口已关闭");
            }catch(Exception e){if(socket==current){disconnect();event("onNativeDisconnected",e.getMessage()==null?"蓝牙连接失败":e.getMessage());}}
        },"HC07-RFCOMM").start();
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] granted) {
        super.onRequestPermissionsResult(request,permissions,granted);
        if(request==CONNECT_PERMISSION){if(granted.length>0 && granted[0]==PackageManager.PERMISSION_GRANTED)chooseDevice();else event("onNativeError","需要“附近设备”连接权限以连接已配对模块");}
    }
    @Override protected void onActivityResult(int request,int result,Intent data) {
        super.onActivityResult(request,result,data);
        if(request==ENABLE_BT){if(result==RESULT_OK)chooseDevice();return;}
        if(request==OPEN_MIDI && nativeMidiChoice){
            if(result==RESULT_OK && data!=null && data.getData()!=null)readMidi(data.getData());
            else {nativeMidiChoice=false;event("onNativeMidiError","已取消选择 MIDI，请重新选择曲谱");}
            return;
        }
        if(request==OPEN_MIDI && fileChoice!=null){
            fileChoice.onReceiveValue(result==RESULT_OK && data!=null && data.getData()!=null?new Uri[]{data.getData()}:null);fileChoice=null;return;
        }
        if(request==SAVE_WAV){
            saveDialog=false;
            if(result!=RESULT_OK || data==null || data.getData()==null){event("onNativeSaveError","已取消导出；完整录音缓存保留，可重新下载导出");return;}
            final Uri target=data.getData();
            saveCopying=true;
            files.execute(()->{
                try(InputStream input=new FileInputStream(wavCache);
                    OutputStream output=getContentResolver().openOutputStream(target,"wt")) {
                    if(output==null)throw new Exception("无法写入所选文件");
                    byte[] buffer=new byte[16384];long copied=0;int n;
                    while((n=input.read(buffer))!=-1){output.write(buffer,0,n);copied+=n;}
                    if(copied!=wavCache.length())throw new Exception("导出长度校验失败");
                    output.flush();js("window.onNativeWrite && window.onNativeWrite(true,'');");
                }catch(Exception e){event("onNativeSaveError",e.toString());}
                finally{saveCopying=false;}
            });
        }
    }

    private void closeWav(){try{wavStore.close();}catch(Exception ignored){}}
    public final class PhoneBridge {
        @JavascriptInterface public void chooseMidi(){runOnUiThread(()->MainActivity.this.chooseMidi());}
        @JavascriptInterface public void chooseDevice(){runOnUiThread(()->MainActivity.this.chooseDevice());}
        @JavascriptInterface public void sendBase64(String encoded){
            final byte[] data;
            try{data=Base64.decode(encoded,Base64.DEFAULT);if(data.length<8 || data.length>72)throw new Exception("串口帧长度无效");}
            catch(Exception e){error(e);return;}
            final OutputStream target=bluetoothOut;
            writes.execute(()->{try{if(target==null || target!=bluetoothOut)throw new Exception("蓝牙未连接");target.write(data);target.flush();}
                catch(Exception e){if(target==bluetoothOut){disconnect();event("onNativeDisconnected",e.toString());}else error(e);}});
        }
        @JavascriptInterface public void beginSave(String name,int frames,int channels){
            files.execute(()->{
                try{
                    if(saveDialog || saveCopying)throw new Exception("已有保存任务");
                    saveName=name;
                    // Do not expose a header-only file in Documents while the
                    // slow HC-07 transfer is still pending. Keep unique caches.
                    wavStore.begin(getCacheDir(),frames,channels);
                    js("window.onNativeSaveReady && window.onNativeSaveReady();");
                }catch(Exception e){closeWav();event("onNativeSaveError",e.toString());}
            });
        }
        @JavascriptInterface public void appendAudio(String encoded){
            files.execute(()->{
                try {
                    byte[] data=Base64.decode(encoded,Base64.DEFAULT);
                    wavStore.append(data);js("window.onNativeWrite && window.onNativeWrite(true,'');");
                }catch(Exception e){closeWav();event("onNativeSaveError",e.toString());}
            });
        }
        @JavascriptInterface public void finishSave(){
            files.execute(()->{
                try{
                    wavCache=wavStore.finish();
                    runOnUiThread(()->{
                        saveDialog=true;
                        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("audio/wav").putExtra(Intent.EXTRA_TITLE,saveName);
                        try{startActivityForResult(intent,SAVE_WAV);}catch(Exception e){saveDialog=false;event("onNativeSaveError",e.toString());}
                    });
                }catch(Exception e){closeWav();event("onNativeSaveError",e.toString());}
            });
        }
        @JavascriptInterface public void cancelSave(){files.execute(()->{closeWav();event("onNativeError","下载中断；未导出残缺文件，应用缓存保留。请重新下载。");});}
    }

    @Override public void onBackPressed(){new AlertDialog.Builder(this).setMessage("退出将断开蓝牙并中断未完成下载。板端录音继续由板卡控制。").setPositiveButton("退出",(d,w)->finish()).setNegativeButton("取消",null).show();}
    @Override protected void onDestroy(){destroyed=true;disconnect();files.execute(()->closeWav());files.shutdown();writes.shutdown();if(fileChoice!=null)fileChoice.onReceiveValue(null);web.removeJavascriptInterface("PhoneNative");web.destroy();super.onDestroy();}
}
