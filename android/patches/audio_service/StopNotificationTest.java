import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.tools.ToolProvider;

/** Runs the compiled upstream methods against a bound-service lifecycle fake. */
class StopNotificationTest {
    public static void main(String[] args) throws Exception {
        String source = Files.readString(Path.of(args[0]));
        String methods = method(source, "public void stop()")
            + method(source, "private void updateNotification()")
            + method(source, "private void deactivateMediaSession()")
            + method(source, "private void releaseWakeLock()");
        Path output = Path.of(args[1]);
        Files.createDirectories(output);
        Path test = output.resolve("BoundAudioService.java");
        Files.writeString(test, HARNESS.replace("// UPSTREAM_METHODS", methods));
        var compiler = ToolProvider.getSystemJavaCompiler();
        if (compiler == null || compiler.run(null, null, null,
                "--release", "17", "-d", output.toString(), test.toString()) != 0) {
            throw new AssertionError("Could not compile audio_service stop regression");
        }
        try (var loader = new URLClassLoader(new java.net.URL[] {output.toUri().toURL()})) {
            loader.loadClass("BoundAudioService").getMethod("main", String[].class)
                .invoke(null, (Object) new String[0]);
        }
    }

    private static String method(String source, String signature) {
        int start = source.indexOf(signature);
        if (start < 0) throw new AssertionError("Missing upstream method: " + signature);
        int body = source.indexOf('{', start);
        int depth = 1;
        int end = body + 1;
        while (depth > 0 && end < source.length()) {
            char character = source.charAt(end++);
            if (character == '{') depth++;
            if (character == '}') depth--;
        }
        if (depth != 0) throw new AssertionError("Unterminated method: " + signature);
        return source.substring(start, end) + "\n";
    }

    // Android keeps a stopped service alive while a browser is bound. Its
    // NotificationManager cannot cancel a foreground-owned notification.
    // These fakes model those constraints; they do not emulate Android UI.
    private static final String HARNESS = """
        public class BoundAudioService {
            static final int NOTIFICATION_ID = 1124;
            static final int STOP_FOREGROUND_REMOVE = 1;
            boolean notificationCreated = true;
            boolean foreground = true;
            boolean notificationVisible = true;
            boolean stopped;
            int notificationUpdates;
            final Session mediaSession = new Session();
            final WakeLock wakeLock = new WakeLock();
            final Handler handler = new Handler();
            final Notifications notifications = new Notifications();

            // UPSTREAM_METHODS

            void stopSelf() { stopped = true; }
            Notifications getNotificationManager() { return notifications; }
            Object buildNotification() { return new Object(); }

            static class ServiceCompat {
                static void stopForeground(BoundAudioService service, int flags) {
                    service.foreground = false;
                    if (flags == STOP_FOREGROUND_REMOVE) service.notificationVisible = false;
                }
            }
            class Notifications {
                void cancel(int id) {
                    if (!foreground) notificationVisible = false;
                }
                void notify(int id, Object notification) {
                    notificationUpdates++;
                    notificationVisible = true;
                }
            }
            static class Session {
                boolean active = true;
                boolean isActive() { return active; }
                void setActive(boolean value) { active = value; }
            }
            static class WakeLock {
                boolean held = true;
                boolean isHeld() { return held; }
                void release() { held = false; }
            }
            static class Handler {
                boolean hasCallbacks = true;
                void removeCallbacksAndMessages(Object token) { hasCallbacks = false; }
            }

            static void require(boolean value, String message) {
                if (!value) throw new AssertionError(message);
            }
            public static void main(String[] args) {
                var service = new BoundAudioService();
                service.stop();
                require(service.stopped, "Service must be stopped");
                require(!service.foreground, "Stopped bound service still owns foreground notification");
                require(!service.notificationVisible, "Stopped bound service notification remains visible");
                require(!service.mediaSession.active, "Media session remains active");
                require(!service.wakeLock.held, "Stopped bound service retains wake lock");
                require(!service.handler.hasCallbacks, "Queued artwork callback was retained");
                service.updateNotification();
                require(!service.notificationVisible, "Late artwork resurrected stopped notification");
                require(service.notificationUpdates == 0, "Stopped notification was republished");
                service.stop();
                require(!service.notificationVisible, "Repeated stop restored notification");
                // A later playback must still be able to publish notifications.
                service.notificationCreated = true;
                service.foreground = true;
                service.updateNotification();
                require(service.notificationVisible, "New playback notification was suppressed");
                require(service.notificationUpdates == 1, "New playback notification was not updated");
                System.out.println("audio_service bound stop regression: 11 assertions passed");
            }
        }
        """;
}
