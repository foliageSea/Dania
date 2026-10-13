package com.foliage.dania.toolbox;

import android.os.ParcelFileDescriptor;

interface IPrivilegedService {
    ParcelFileDescriptor startCommand(String id, String command) = 0;
    int waitForCommand(String id) = 1;
    void cancelCommand(String id) = 2;
    String listFiles(String path) = 3;
    ParcelFileDescriptor openFile(String path, boolean write) = 4;
    void destroy() = 16777114;
}
