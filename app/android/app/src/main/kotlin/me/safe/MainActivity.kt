package me.safe

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val TRACES_CHANNEL = "me.safe/traces"
        const val SYSTEM_CHANNEL = "me.safe/system"
    }

    private var locationChannel: LocationChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android photographie l'écran de chaque app pour l'écran « applis
        // récentes », et garde l'image sur disque. Pour l'application, cette image
        // est une carte centrée sur l'endroit où se trouvait la personne : la
        // trace de localisation la plus lisible du téléphone, hors de notre
        // base et hors de toute purge que nous pourrions écrire.
        //
        // À partir d'Android 13, on peut refuser l'instantané sans rien
        // interdire d'autre — les captures d'écran volontaires continuent de
        // marcher. En dessous, seul `FLAG_SECURE` en viendrait à bout, au prix
        // de bloquer aussi les captures : arbitrage non tranché, et le parc de
        // la bêta est en Android 13+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = LocationChannel(this)
        locationChannel = channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LocationChannel.CHANNEL,
        ).setMethodCallHandler(channel)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LocationChannel.STREAM_CHANNEL,
        ).setStreamHandler(channel)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRACES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sweep" -> result.success(TraceSweeper.sweep(this))
                    // Le §4.6 demande de noter le modèle avec les mesures de la
                    // file hors-ligne : un geste perdu peut l'être par la
                    // surcouche du constructeur et pas par le code. Lu ici, il
                    // ne part nulle part tout seul — il n'apparaît que dans le
                    // rapport que le testeur copie lui-même.
                    "deviceModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})")
                    else -> result.notImplemented()
                }
            }

        // Ouvrir une adresse dans le navigateur. Trois lignes d'Intent plutôt
        // que le paquet `url_launcher` : une dépendance de plus à justifier
        // devant F-Droid (§12.6), et un manifeste qu'elle modifie par fusion.
        // Le seul appelant est le bandeau de mise à jour, et l'adresse qu'il
        // passe a déjà été contrainte à notre domaine côté Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("argument", "url manquante", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * L'alarme d'oubli n'est armée que pendant que l'app est hors de l'écran, et
     * une purge de rattrapage a lieu à chaque retour : si le téléphone était
     * éteint à l'heure dite, l'alarme perdue est sans conséquence.
     */
    override fun onStart() {
        super.onStart()
        TraceSweeper.cancel(this)
        TraceSweeper.sweep(this)
    }

    override fun onStop() {
        super.onStop()
        // Une purge à l'âge tout de suite, puis l'alarme pour le reste : quitter
        // l'écran est le moment le moins cher pour effacer, personne ne lit.
        TraceSweeper.sweep(this)
        TraceSweeper.schedule(this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (locationChannel?.onRequestPermissionsResult(requestCode, permissions, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
