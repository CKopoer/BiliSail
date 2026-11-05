import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import org.json.JSONArray;
import org.json.JSONObject;

// Read-only diagnostic runnable with app_process; no APK, permission or account.
final class AndroidCodecCapabilities {
    public static void main(String[] args) throws Exception {
        JSONArray rows = new JSONArray();
        for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (info.isEncoder()) continue;
            for (String mime : info.getSupportedTypes()) {
                if (!mime.equals("video/avc") && !mime.equals("video/hevc") && !mime.equals("video/av01")) continue;
                JSONObject row = new JSONObject();
                row.put("name", info.getName());
                row.put("mime", mime);
                row.put("hardwareAccelerated", info.isHardwareAccelerated());
                row.put("softwareOnly", info.isSoftwareOnly());
                row.put("vendor", info.isVendor());
                try {
                    MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(mime);
                    MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
                    row.put("advertises3840x2160At60", video.areSizeAndRateSupported(3840, 2160, 60));
                    JSONArray profiles = new JSONArray();
                    for (MediaCodecInfo.CodecProfileLevel profile : caps.profileLevels) {
                        JSONObject entry = new JSONObject();
                        entry.put("profile", profile.profile);
                        entry.put("level", profile.level);
                        profiles.put(entry);
                    }
                    row.put("profiles", profiles);
                } catch (Exception error) {
                    row.put("capabilityError", error.getClass().getSimpleName());
                }
                rows.put(row);
            }
        }
        System.out.println(rows.toString());
    }
}
