package com.foliage.dania.toolbox;

import android.os.ParcelFileDescriptor;

interface IPrivilegedService {
    ParcelFileDescriptor startCommand(String id, String command) = 0;
    int waitForCommand(String id) = 1;
    void cancelCommand(String id) = 2;
    String listFiles(String path) = 3;
    ParcelFileDescriptor openFile(String path, boolean write) = 4;
    ParcelFileDescriptor openTerminal(String id, int columns, int rows, String libraryPath) = 5;
    void resizeTerminal(String id, int columns, int rows) = 6;
    int waitForTerminal(String id) = 7;
    void closeTerminal(String id) = 8;
    void destroy() = 16777114;
}
