package oss.krtirtho.spotube

import android.app.AlertDialog
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val activationUrl =
        "https://raw.githubusercontent.com/miscojones3434/pt34-music-spotube/master/activation/allowed_devices.json"

    private val prefs by lazy {
        getSharedPreferences("pt34_music_activation", MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.decorView.post {
            checkActivation()
        }
    }

    private fun getDeviceCode(): String {
        val androidId = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ANDROID_ID,
        ) ?: "unknown"

        val raw = "PT34-MUSIC|$packageName|$androidId"

        val hash = MessageDigest
            .getInstance("SHA-256")
            .digest(raw.toByteArray(Charsets.UTF_8))

        return hash.joinToString("") {
            "%02X".format(it.toInt() and 0xFF)
        }.take(20)
    }

    private fun checkActivation() {
        val savedCode = prefs
            .getString("activation_code", "")
            ?.trim()
            .orEmpty()

        val validUntil = prefs.getLong("activation_valid_until", 0L)

        if (
            savedCode.isNotEmpty() &&
            System.currentTimeMillis() < validUntil
        ) {
            return
        }

        showActivationDialog(
            deviceCode = getDeviceCode(),
            currentCode = savedCode,
        )
    }

    private fun showActivationDialog(
        deviceCode: String,
        currentCode: String,
    ) {
        val padding = (22 * resources.displayMetrics.density).toInt()

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, 0)
        }

        val information = TextView(this).apply {
            text =
                "Este móvil necesita activación.\n\n" +
                "Código del dispositivo:\n$deviceCode\n\n" +
                "Añade este código en tu GitHub y usa la clave que tú hayas creado."
            textSize = 16f
            gravity = Gravity.CENTER_HORIZONTAL
        }

        val input = EditText(this).apply {
            hint = "Código de activación"
            setText(currentCode)
            inputType =
                InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
        }

        container.addView(information)
        container.addView(input)

        val dialog = AlertDialog.Builder(this)
            .setTitle("Activar PT34-MUSIC")
            .setView(container)
            .setCancelable(false)
            .setNegativeButton("Salir") { _, _ ->
                finishAndRemoveTask()
            }
            .setPositiveButton("Activar", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener {
                    val activationCode = input.text.toString().trim()

                    if (activationCode.isEmpty()) {
                        input.error = "Introduce el código"
                        return@setOnClickListener
                    }

                    dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                        .isEnabled = false

                    validateRemote(
                        deviceCode = deviceCode,
                        activationCode = activationCode,
                    ) { allowed ->
                        dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                            .isEnabled = true

                        if (!allowed) {
                            input.error = "Código no autorizado"
                            return@validateRemote
                        }

                        prefs.edit()
                            .putString("activation_code", activationCode)
                            .putLong(
                                "activation_valid_until",
                                System.currentTimeMillis() +
                                    7L * 24L * 60L * 60L * 1000L,
                            )
                            .apply()

                        Toast.makeText(
                            this,
                            "PT34-MUSIC activado",
                            Toast.LENGTH_SHORT,
                        ).show()

                        dialog.dismiss()
                    }
                }
        }

        dialog.show()
    }

    private fun validateRemote(
        deviceCode: String,
        activationCode: String,
        onResult: (Boolean) -> Unit,
    ) {
        thread {
            val valid = runCatching {
                val connection =
                    URL(activationUrl).openConnection() as HttpURLConnection

                connection.connectTimeout = 10000
                connection.readTimeout = 10000
                connection.requestMethod = "GET"
                connection.setRequestProperty("Cache-Control", "no-cache")

                try {
                    if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                        return@runCatching false
                    }

                    val body = connection.inputStream
                        .bufferedReader()
                        .use { it.readText() }

                    val devices =
                        JSONObject(body).optJSONArray("devices")
                            ?: return@runCatching false

                    for (index in 0 until devices.length()) {
                        val item = devices.optJSONObject(index) ?: continue

                        val enabled = item.optBoolean("enabled", true)
                        val storedDevice = item.optString("device_id")
                        val storedCode = item.optString("code")

                        if (
                            enabled &&
                            storedDevice.equals(
                                deviceCode,
                                ignoreCase = true,
                            ) &&
                            storedCode == activationCode
                        ) {
                            return@runCatching true
                        }
                    }

                    false
                } finally {
                    connection.disconnect()
                }
            }.getOrDefault(false)

            runOnUiThread {
                onResult(valid)
            }
        }
    }
}
