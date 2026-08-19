import java.util.*;
import java.util.regex.*;
import java.io.*;
import java.nio.charset.StandardCharsets;

/**
 * Regex corpus runner for Java.
 * Usage: java run_java.java < input.json
 * stdin:  JSON array of {id, pattern, testText, flags}
 * stdout: JSON object of {id: {matches: [{match, index}], error}}
 */
public class run_java {

    // Minimal JSON string escaper
    private static String jsonEscape(String s) {
        if (s == null) return "null";
        StringBuilder sb = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':  sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
        return sb.toString();
    }

    // Extract string value for a key from a flat JSON object string
    // Handles simple escaped chars only — sufficient for well-formed corpus input
    private static String extractField(String obj, String key) {
        String search = "\"" + key + "\"";
        int ki = obj.indexOf(search);
        if (ki < 0) return "";
        int colon = obj.indexOf(':', ki + search.length());
        if (colon < 0) return "";
        int start = obj.indexOf('"', colon + 1);
        if (start < 0) return "";
        StringBuilder sb = new StringBuilder();
        int i = start + 1;
        while (i < obj.length()) {
            char c = obj.charAt(i);
            if (c == '\\' && i + 1 < obj.length()) {
                char next = obj.charAt(i + 1);
                switch (next) {
                    case '"':  sb.append('"');  i += 2; continue;
                    case '\\': sb.append('\\'); i += 2; continue;
                    case 'n':  sb.append('\n'); i += 2; continue;
                    case 'r':  sb.append('\r'); i += 2; continue;
                    case 't':  sb.append('\t'); i += 2; continue;
                    case 'u':
                        if (i + 5 < obj.length()) {
                            String hex = obj.substring(i + 2, i + 6);
                            sb.append((char) Integer.parseInt(hex, 16));
                            i += 6; continue;
                        }
                }
                sb.append(next); i += 2;
            } else if (c == '"') {
                break;
            } else {
                sb.append(c); i++;
            }
        }
        return sb.toString();
    }

    // Split top-level JSON array into individual object strings
    private static List<String> splitJsonArray(String json) {
        List<String> items = new ArrayList<>();
        int depth = 0;
        int start = -1;
        for (int i = 0; i < json.length(); i++) {
            char c = json.charAt(i);
            if (c == '{') {
                if (depth == 0) start = i;
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth == 0 && start >= 0) {
                    items.add(json.substring(start, i + 1));
                    start = -1;
                }
            }
        }
        return items;
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(
            new InputStreamReader(System.in, StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) sb.append(line).append('\n');
        String input = sb.toString().trim();

        List<String> entries = splitJsonArray(input);
        StringBuilder out = new StringBuilder("{");
        boolean first = true;

        for (String entry : entries) {
            String id       = extractField(entry, "id");
            String pattern  = extractField(entry, "pattern");
            String testText = extractField(entry, "testText");
            String flags    = extractField(entry, "flags");

            if (!first) out.append(",");
            first = false;
            out.append(jsonEscape(id)).append(":");

            try {
                int opts = 0;
                if (flags.contains("i")) opts |= Pattern.CASE_INSENSITIVE;
                if (flags.contains("m")) opts |= Pattern.MULTILINE;
                if (flags.contains("s")) opts |= Pattern.DOTALL;
                if (flags.contains("x")) opts |= Pattern.COMMENTS;

                Pattern rx = Pattern.compile(pattern, opts);
                Matcher matcher = rx.matcher(testText);

                // Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
                // and matches the bridge's behavior.
                List<String> matchParts = new ArrayList<>();
                while (matcher.find()) {
                    String matchVal = matcher.group();
                    int index = matcher.start();
                    matchParts.add("{\"match\":" + jsonEscape(matchVal) + ",\"index\":" + index + "}");
                }

                out.append("{\"matches\":[");
                out.append(String.join(",", matchParts));
                out.append("],\"error\":null}");

            } catch (Exception ex) {
                out.append("{\"matches\":[],\"error\":");
                out.append(jsonEscape(ex.getMessage()));
                out.append("}");
            }
        }

        out.append("}");
        System.out.print(out);
    }
}
