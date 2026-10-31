package io.openflux.app;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.widget.Toast;
import java.io.InputStream;
import java.util.Collections;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.RGBLuminanceSource;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.integration.android.IntentIntegrator;
import org.json.JSONObject;
import io.openflux.bridge.mobile.Mobile;

// openflux:// links in: a link opened from a chat or the system camera, the
// in-app QR scanner, or a QR read off a photo. The core reads the link; this
// asks before adding the profile and words what the core rejected.
final class ShareLinks {
    private final MainActivity app;

    ShareLinks(MainActivity app) {
        this.app = app;
    }

    void promptImportKey() {
        AlertDialog.Builder builder = new AlertDialog.Builder(app, app.darkMode
                ? android.R.style.Theme_DeviceDefault_Dialog_Alert
                : android.R.style.Theme_DeviceDefault_Light_Dialog_Alert);
        builder.setTitle("Импорт по ключу или ссылке");

        LinearLayout container = new LinearLayout(app);
        container.setOrientation(LinearLayout.VERTICAL);
        container.setPadding(app.dp(20), app.dp(12), app.dp(20), app.dp(8));

        TextView hint = app.text("Вставьте ключ подключения или ссылку openflux://:", 13, app.secondary, false);
        container.addView(hint);

        EditText input = new EditText(app);
        input.setHint("openflux://v1/...");
        input.setSingleLine(false);
        input.setMaxLines(5);
        input.setTextSize(14);
        input.setTextColor(app.text);
        input.setHintTextColor(app.secondary);
        input.setBackground(app.rounded(app.tonal(0.08f), app.border, 1, 10));
        input.setPadding(app.dp(12), app.dp(10), app.dp(12), app.dp(10));
        LinearLayout.LayoutParams inputParams = new LinearLayout.LayoutParams(-1, -2);
        inputParams.topMargin = app.dp(10);
        container.addView(input, inputParams);

        ClipboardManager cm = (ClipboardManager) app.getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null && cm.hasPrimaryClip() && cm.getPrimaryClip() != null && cm.getPrimaryClip().getItemCount() > 0) {
            CharSequence clip = cm.getPrimaryClip().getItemAt(0).getText();
            if (clip != null) {
                String clipStr = clip.toString().trim();
                if (clipStr.startsWith("openflux://") || clipStr.startsWith("v1/")) {
                    input.setText(clipStr);
                    input.setSelection(clipStr.length());
                }
            }
        }

        builder.setView(container);
        builder.setPositiveButton("Добавить", (dialog, which) -> {
            String text = input.getText().toString().trim();
            if (text.isEmpty()) {
                Toast.makeText(app, "Введите ключ или ссылку", Toast.LENGTH_SHORT).show();
                return;
            }
            if (!text.startsWith("openflux://")) {
                if (text.startsWith("v1/")) {
                    text = "openflux://" + text;
                } else if (!text.contains("://")) {
                    text = "openflux://v1/" + text;
                }
            }
            importShareLink(text);
        });
        builder.setNegativeButton("Отмена", null);
        builder.show();
    }

    void handleShareIntent(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction()) || intent.getData() == null) return;
        importShareLink(intent.getData().toString());
        // Not again on a configuration change.
        intent.setAction(Intent.ACTION_MAIN);
    }

    void scanShareQr() {
        new IntentIntegrator(app)
                .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
                .setPrompt("Наведите камеру на QR-код OpenFlux")
                .setBeepEnabled(false)
                .setOrientationLocked(true)
                .initiateScan();
    }

    void pickShareQrImage() {
        Intent pick = new Intent(Intent.ACTION_GET_CONTENT);
        pick.setType("image/*");
        pick.addCategory(Intent.CATEGORY_OPENABLE);
        app.startActivityForResult(Intent.createChooser(pick, "Выберите фото с QR-кодом"), MainActivity.QR_IMAGE_REQUEST);
    }

    void importQrImage(Uri uri) {
        new Thread(() -> {
            String result = null;
            String error = null;
            Bitmap bitmap = null;
            try {
                BitmapFactory.Options bounds = new BitmapFactory.Options();
                bounds.inJustDecodeBounds = true;
                try (InputStream stream = app.getContentResolver().openInputStream(uri)) {
                    if (stream == null) throw new IllegalArgumentException("Не удалось открыть фото");
                    BitmapFactory.decodeStream(stream, null, bounds);
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    throw new IllegalArgumentException("Файл не является изображением");
                }
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inSampleSize = 1;
                while (Math.max(bounds.outWidth / options.inSampleSize,
                        bounds.outHeight / options.inSampleSize) > 2048) options.inSampleSize *= 2;
                try (InputStream stream = app.getContentResolver().openInputStream(uri)) {
                    if (stream == null) throw new IllegalArgumentException("Не удалось открыть фото");
                    bitmap = BitmapFactory.decodeStream(stream, null, options);
                }
                if (bitmap == null) throw new IllegalArgumentException("Не удалось прочитать фото");
                int width = bitmap.getWidth(), height = bitmap.getHeight();
                int[] pixels = new int[width * height];
                bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
                BinaryBitmap image = new BinaryBitmap(new HybridBinarizer(
                        new RGBLuminanceSource(width, height, pixels)));
                java.util.Map<DecodeHintType, Object> hints = new java.util.EnumMap<>(DecodeHintType.class);
                hints.put(DecodeHintType.POSSIBLE_FORMATS,
                        java.util.Collections.singletonList(BarcodeFormat.QR_CODE));
                hints.put(DecodeHintType.TRY_HARDER, Boolean.TRUE);
                result = new MultiFormatReader().decode(image, hints).getText();
            } catch (Exception e) {
                error = e instanceof com.google.zxing.NotFoundException
                        ? "На фото нет QR-кода" : "Не удалось прочитать фото: " + e.getMessage();
            } finally {
                if (bitmap != null) bitmap.recycle();
            }
            String link = result, problem = error;
            app.runOnUiThread(() -> {
                if (link != null) importShareLink(link);
                else Toast.makeText(app, problem, Toast.LENGTH_LONG).show();
            });
        }, "read-share-qr-image").start();
    }

    // Turns an openflux:// link into a profile after the user confirms: the
    // link carries the exit's key, so nothing is saved silently.
    void importShareLink(String link) {
        Profile p;
        try {
            JSONObject read = new JSONObject(Mobile.readShareLink(link.trim()));
            if (!read.has("config")) {
                // A dialog, not a toast: Android cuts a toast to two lines.
                new AlertDialog.Builder(app, app.darkMode
                        ? android.R.style.Theme_DeviceDefault_Dialog_Alert
                        : android.R.style.Theme_DeviceDefault_Light_Dialog_Alert)
                        .setTitle("Не удалось добавить профиль")
                        .setMessage(shareLinkProblem(read, link.trim()))
                        .setPositiveButton("OK", null)
                        .show();
                return;
            }
            p = Profile.fromShare(read.getJSONObject("config"));
        } catch (Exception e) {
            Toast.makeText(app, "Не удалось прочитать QR: " + e.getMessage(), Toast.LENGTH_LONG).show();
            return;
        }
        new AlertDialog.Builder(app, app.darkMode
                ? android.R.style.Theme_DeviceDefault_Dialog_Alert
                : android.R.style.Theme_DeviceDefault_Light_Dialog_Alert)
                .setTitle("Добавить профиль?")
                .setMessage(p.name + "\n" + app.profileTransportSummary(p) + (p.stream
                        ? "\n\nВ коде адрес PHP-ноды: добавляйте QR только от тех, кому доверяете."
                        : "\n\nВ коде ключ шифрования ноды: добавляйте QR только от тех, кому доверяете."))
                .setPositiveButton("Добавить", (dialog, which) -> {
                    app.profiles.add(p);
                    app.profileStore.save(app.profiles);
                    if (app.isConnectionRunning()) app.showPage(MainActivity.PAGE_PROFILES);
                    else app.selectProfile(p.id);
                    app.appendLog("Профиль «" + p.name + "» добавлен по QR");
                    Toast.makeText(app, "Профиль добавлен", Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    // Why the core rejected a link (share.Result's code and param), in the
    // user's words; the core's English detail is the fallback.
    private static String shareLinkProblem(JSONObject r, String link) {
        String param = r.optString("param");
        switch (r.optString("code")) {
            case "not_link": return "Это не ссылка OpenFlux";
            // Any openflux:// link not under v1/: a newer format, or a start
            // mangled on the way. Shows the start (no further: the payload
            // carries the key), so a report says which.
            case "unsupported_version": return "Ссылка начинается с «" + link.substring(0, Math.min(14, link.length()))
                    + "…», а приложение понимает «openflux://v1/…». Скопируйте её заново; если начало верное, ссылка из более новой версии OpenFlux";
            case "case_changed": return "В ссылке по дороге поменялся регистр букв: скопируйте её заново";
            case "damaged": return "Ссылка повреждена или обрезана: скопируйте её заново";
            case "too_large": return "Ссылка слишком большая";
            case "bad_payload":
            case "bad_config": return "В ссылке нет настроек подключения";
            case "no_transports": return "В ссылке не указан ни один транспорт";
            case "several_need_session": return "Несколько транспортов работают только в режиме Session, а в ссылке он выключен";
            case "session_secret": return "Для Session нужен ключ шифрования не короче " + param + " символов";
            case "short_secret": return "Ключ шифрования в ссылке короче " + param + " символов";
            case "unknown_codec": return "Неизвестный кодек «" + param + "»: обновите приложение";
            case "not_shareable": return "MAX нельзя передать ссылкой: токен привязан к одному аккаунту";
            case "unknown_transport": return "Неизвестный транспорт «" + param + "»: обновите приложение";
            case "direct_no_dial": return "Direct: в ссылке нет адреса ноды";
            case "direct_needs_session": return "Direct работает только в режиме Session";
            case "unknown_mode": return "Неизвестный режим «" + param + "»: обновите приложение";
            case "stream_transport": return "Режим без сервера работает только через Cups.online или Mail.ru, а в ссылке "
                    + Profile.transportLabel(param);
            case "stream_one_transport": return "В режиме без сервера должен быть ровно один транспорт";
            case "stream_plain_only": return "В режиме без сервера нет ключа шифрования и Session, а в ссылке они есть";
            default: return "Не удалось прочитать ссылку: " + r.optString("error");
        }
    }
}
