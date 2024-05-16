package com.example.rfid_scanner;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import com.android.hdhe.uhf.reader.UhfReader;
import com.android.hdhe.uhf.readerInterface.TagModel;
import cn.pda.serialport.Tools;
import java.util.List;
import android.os.Handler;
import android.os.Looper;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.rfid_scanner/channel";
    private UhfReader uhfReader;
    private Handler handler = new Handler(Looper.getMainLooper());
    private boolean isScanning = false;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        uhfReader = UhfReader.getInstance();
        if (uhfReader != null) {
            uhfReader.setOutputPower(26);
        }

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("scanTag")) {
                    scanForFirstTag(result);
                } else {
                    result.notImplemented();
                }
            });
    }

    private void scanForFirstTag(MethodChannel.Result result) {
        if (uhfReader == null) {
            result.error("READER_NOT_INITIALIZED", "UHF Reader is not initialized", null);
            return;
        }

        isScanning = true;

        handler.postDelayed(() -> {
            if (isScanning) {
                isScanning = false;
                result.error("TIMEOUT", "No RFID tag detected within the timeout period", null);
            }
        }, 10000); // 10-second timeout

        new Thread(() -> {
            try {
                while (isScanning) {
                    List<TagModel> tags = uhfReader.inventoryRealTime(); // Real-time inventory
                    if (tags != null && !tags.isEmpty()) {
                        isScanning = false;
                        byte[] epcBytes = tags.get(0).getmEpcBytes(); // Fetch the EPC bytes of the first detected tag
                        String tagData = Tools.Bytes2HexString(epcBytes, epcBytes.length); // Convert byte array to hex string using Tools class

                        handler.post(() -> {
                            if (!isScanning) {
                                result.success(tagData);
                            }
                        });
                        return;
                    }

                    Thread.sleep(100); // Small delay between scans to prevent CPU overuse
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                if (isScanning) {
                    isScanning = false;
                    handler.post(() -> result.error("INTERRUPTED", "Scan was interrupted", null));
                }
            } catch (Exception e) {
                if (isScanning) {
                    isScanning = false;
                    handler.post(() -> result.error("ERROR", "An error occurred during scanning: " + e.getMessage(), null));
                }
            }
        }).start();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (uhfReader != null) {
            uhfReader.close(); // Properly close the UHF reader
        }
    }
}
