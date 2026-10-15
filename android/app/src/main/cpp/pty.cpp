#include <jni.h>
#include <cerrno>
#include <climits>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <string>
#include <vector>

extern char** environ;

static void fail(JNIEnv* env, const char* operation, int error = errno) {
    std::string message = std::string(operation) + ": " + std::strerror(error);
    env->ThrowNew(env->FindClass("java/io/IOException"), message.c_str());
}

static bool validSize(JNIEnv* env, jint columns, jint rows) {
    if (columns >= 2 && columns <= 1000 && rows >= 1 && rows <= 1000) return true;
    env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid terminal size");
    return false;
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_foliage_dania_toolbox_NativePty_spawn(JNIEnv* env, jobject, jint columns, jint rows) {
    if (!validSize(env, columns, rows)) return nullptr;
    jintArray result = env->NewIntArray(2);
    if (!result) return nullptr;
    int master = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (master < 0) { fail(env, "posix_openpt"); return nullptr; }
    auto masterFailure = [&](const char* operation) -> jintArray {
        int error = errno; close(master); fail(env, operation, error); return nullptr;
    };
    if (grantpt(master) || unlockpt(master)) return masterFailure("unlock PTY");
    char name[PATH_MAX];
    int nameError = ptsname_r(master, name, sizeof(name));
    if (nameError) { errno = nameError; return masterFailure("ptsname_r"); }
    int slave = open(name, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (slave < 0) return masterFailure("open PTY slave");
    winsize size{};
    size.ws_col = static_cast<unsigned short>(columns);
    size.ws_row = static_cast<unsigned short>(rows);
    termios settings{};
    if (tcgetattr(slave, &settings) == 0) {
        settings.c_iflag |= ICRNL | IXON | IUTF8;
        settings.c_oflag |= OPOST | ONLCR;
        settings.c_lflag |= ISIG | ICANON | ECHO | ECHOE | ECHOK;
        settings.c_cc[VERASE] = 127;
        settings.c_cc[VINTR] = 3;
        settings.c_cc[VEOF] = 4;
        tcsetattr(slave, TCSANOW, &settings);
    }
    if (ioctl(slave, TIOCSWINSZ, &size) < 0) {
        int error = errno; close(slave); errno = error; return masterFailure("set PTY size");
    }
    int errors[2];
    if (pipe2(errors, O_CLOEXEC) < 0) {
        int error = errno; close(slave); errno = error; return masterFailure("exec error pipe");
    }
    // Prepare everything before fork: the child must never allocate or enter JNI.
    std::vector<std::string> environment;
    for (char** item = environ; *item; ++item) {
        if (strncmp(*item, "TERM=", 5) && strncmp(*item, "HOME=", 5) &&
            strncmp(*item, "SHELL=", 6) && strncmp(*item, "COLORTERM=", 10))
            environment.emplace_back(*item);
    }
    environment.emplace_back("TERM=xterm-256color");
    environment.emplace_back("COLORTERM=truecolor");
    environment.emplace_back("HOME=/data/local/tmp");
    environment.emplace_back("SHELL=/system/bin/sh");
    std::vector<char*> variables;
    for (auto& value : environment) variables.push_back(value.data());
    variables.push_back(nullptr);
    char** envp = variables.data();
    char shell[] = "/system/bin/sh";
    char interactive[] = "-i";
    char* argv[] = {shell, interactive, nullptr};
    long fdLimit = sysconf(_SC_OPEN_MAX);
    if (fdLimit < 0) fdLimit = 65536;
    sigset_t emptySignals;
    sigemptyset(&emptySignals);
    struct sigaction defaultSignal{};
    defaultSignal.sa_handler = SIG_DFL;
    sigemptyset(&defaultSignal.sa_mask);
    pid_t pid = fork();
    if (pid == 0) {
        close(errors[0]);
        int error = 0;
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0) error = errno;
        if (!error) {
            for (int fd = 0; fd <= 2; ++fd) {
                if (dup2(slave, fd) < 0) { error = errno; break; }
                fcntl(fd, F_SETFD, 0);
            }
        }
        if (!error) {
            sigprocmask(SIG_SETMASK, &emptySignals, nullptr);
            for (int signal : {SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE, SIGCHLD, SIGTSTP, SIGTTIN, SIGTTOU})
                sigaction(signal, &defaultSignal, nullptr);
            for (int fd = 3; fd < fdLimit; ++fd) if (fd != errors[1]) close(fd);
            chdir("/data/local/tmp");
            execve(shell, argv, envp);
            error = errno;
        }
        // A failed exec is reported to the parent, then exits without JVM cleanup.
        ssize_t ignored = write(errors[1], &error, sizeof(error));
        (void)ignored;
        _exit(127);
    }
    int forkError = errno;
    close(slave);
    close(errors[1]);
    if (pid < 0) {
        close(errors[0]); close(master); fail(env, "fork", forkError); return nullptr;
    }
    int childError = 0;
    ssize_t count;
    do { count = read(errors[0], &childError, sizeof(childError)); } while (count < 0 && errno == EINTR);
    int pipeError = errno;
    close(errors[0]);
    if (count != 0) {
        kill(pid, SIGKILL);
        while (waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
        close(master);
        fail(env, "exec shell", count > 0 ? childError : pipeError);
        return nullptr;
    }
    jint values[] = {master, pid};
    env->SetIntArrayRegion(result, 0, 2, values);
    if (env->ExceptionCheck()) {
        close(master); kill(-pid, SIGKILL); kill(pid, SIGKILL);
        while (waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
        return nullptr;
    }
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_foliage_dania_toolbox_NativePty_resize(JNIEnv* env, jobject, jint fd, jint columns, jint rows) {
    if (!validSize(env, columns, rows)) return;
    winsize size{};
    size.ws_col = static_cast<unsigned short>(columns);
    size.ws_row = static_cast<unsigned short>(rows);
    if (ioctl(fd, TIOCSWINSZ, &size) < 0) fail(env, "resize PTY");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_foliage_dania_toolbox_NativePty_waitFor(JNIEnv* env, jobject, jint pid) {
    int status;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) { fail(env, "waitpid"); return -1; }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

extern "C" JNIEXPORT void JNICALL
Java_com_foliage_dania_toolbox_NativePty_terminate(JNIEnv*, jobject, jint fd, jint pid) {
    pid_t foreground = tcgetpgrp(fd);
    // Interactive jobs have separate process groups. Collect this PTY's session
    // before killing its leader so background jobs are also closed on disconnect.
    std::vector<pid_t> jobs;
    if (pid > 0) {
        DIR* processes = opendir("/proc");
        if (processes) {
            while (dirent* entry = readdir(processes)) {
                char* end = nullptr;
                long candidate = strtol(entry->d_name, &end, 10);
                if (end != entry->d_name && *end == 0 && candidate > 0 && candidate <= INT_MAX &&
                    getsid(static_cast<pid_t>(candidate)) == pid)
                    jobs.push_back(static_cast<pid_t>(candidate));
            }
            closedir(processes);
        }
    }
    for (pid_t job : jobs) if (job != pid) kill(job, SIGHUP);
    for (pid_t job : jobs) if (job != pid) kill(job, SIGKILL);
    if (foreground > 0) kill(-foreground, SIGHUP);
    if (pid > 0) { kill(-pid, SIGHUP); kill(pid, SIGHUP); }
    if (foreground > 0) kill(-foreground, SIGKILL);
    if (pid > 0) { kill(-pid, SIGKILL); kill(pid, SIGKILL); }
}
