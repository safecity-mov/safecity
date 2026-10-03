package me.safe

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Localisation ponctuelle, par le LocationManager d'Android et rien d'autre.
 *
 * Écrit à la main plutôt que délégué à `geolocator` (SPEC §12.6) : ce paquet lie
 * `play-services-location` dans l'APK même quand on lui demande le
 * LocationManager natif. L'option `forceLocationManager` ne change que le chemin
 * d'exécution, pas le contenu du binaire — vérifié sur l'APK construit, qui
 * embarquait 17 classes `com.google.android.gms`. F-Droid refuse les dépendances
 * propriétaires, donc elles ne doivent pas être dans l'arbre de build du tout.
 *
 * L'app n'a besoin que d'un point, au moment d'un geste explicite. Il n'y a ni
 * suivi continu, ni service de premier plan, ni permission d'arrière-plan (§11.1).
 */
class LocationChannel(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val CHANNEL = "me.safe/location"
        const val STREAM_CHANNEL = "me.safe/location/stream"
        private const val PERMISSION_REQUEST = 4711

        /// Cadence du suivi pendant que la carte est à l'écran. Un cycliste à
        /// 20 km/h parcourt une trentaine de mètres en 5 s : assez fin pour que
        /// l'indicateur suive sans faire chauffer le GPS inutilement.
        private const val UPDATE_INTERVAL_MS = 5_000L
        private const val UPDATE_DISTANCE_M = 10f

        /// Âge au-delà duquel on attend un nouveau fix plutôt que de se contenter
        /// du dernier point connu.
        private const val MAX_AGE_MS = 60_000L
    }

    private val locationManager by lazy {
        activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    }

    private var pendingPermission: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "isLocationEnabled" -> result.success(isLocationEnabled())
            "requestPermission" -> requestPermission(result)
            "getCurrentPosition" -> {
                val timeoutMs = (call.argument<Int>("timeoutMs") ?: 12_000).toLong()
                getCurrentPosition(timeoutMs, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun isLocationEnabled(): Boolean =
        locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        // Une seule demande à la fois : la seconde est refusée plutôt que de
        // laisser deux résultats se disputer le même callback.
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.any { it == PackageManager.PERMISSION_GRANTED }

        // Beaucoup d'utilisateurs accordent la position « une seule fois », et
        // Android la révoque à chaque passage en arrière-plan. Le suivi s'est
        // donc abonné à un flux qu'`onListen` a laissé muet, faute de
        // permission — sans erreur, donc sans que Flutter puisse le savoir.
        // Maintenant qu'elle est accordée, on le réarme ici : sans cela le
        // suivi reste mort pour toute la session, l'indicateur ne bouge plus,
        // et chaque geste rouvre une lecture ponctuelle.
        if (granted && streamSink != null) {
            startUpdates()
        }

        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    /**
     * Renvoie une position, ou `null`.
     *
     * `null` n'est pas une erreur : le serveur accepte une action sans position,
     * elle pèse simplement moins (§6.2). Refuser la localisation doit rester un
     * usage possible de l'app.
     */
    private fun getCurrentPosition(timeoutMs: Long, result: MethodChannel.Result) {
        if (!hasPermission() || !isLocationEnabled()) {
            result.success(null)
            return
        }

        val replied = java.util.concurrent.atomic.AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())

        fun reply(location: Location?) {
            if (replied.compareAndSet(false, true)) {
                result.success(
                    location?.let {
                        mapOf(
                            "lat" to it.latitude,
                            "lng" to it.longitude,
                            "accuracy" to it.accuracy.toDouble(),
                        )
                    },
                )
            }
        }

        // Un point connu récent suffit, et évite les 4 à 7 secondes d'attente d'un
        // nouveau fix. La position du déclarant ne sert qu'à un palier à trois
        // valeurs — 50 m, 500 m, au-delà (§6.2) : à l'arrêt ou au pas, une minute
        // d'ancienneté ne change pas le palier. C'est la position du *danger* qui
        // doit être exacte, et elle vient du pin, pas du capteur (§11.6).
        val recent = lastKnown()
        if (recent != null && System.currentTimeMillis() - recent.time < MAX_AGE_MS) {
            reply(recent)
            return
        }

        val provider = when {
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            else -> LocationManager.NETWORK_PROVIDER
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val signal = CancellationSignal()
                locationManager.getCurrentLocation(
                    provider,
                    signal,
                    activity.mainExecutor,
                ) { location -> reply(location ?: lastKnown()) }
                handler.postDelayed({
                    if (!replied.get()) {
                        signal.cancel()
                        reply(lastKnown())
                    }
                }, timeoutMs)
            } else {
                // API 26–29 : pas de getCurrentLocation, on prend une seule mise à
                // jour et on se désabonne aussitôt. Aucun suivi ne subsiste.
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        locationManager.removeUpdates(this)
                        reply(location)
                    }

                    @Deprecated("Requis par l'interface sur les API < 29")
                    override fun onStatusChanged(p: String?, s: Int, e: Bundle?) = Unit

                    override fun onProviderEnabled(provider: String) = Unit
                    override fun onProviderDisabled(provider: String) = Unit
                }
                locationManager.requestLocationUpdates(
                    provider,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper(),
                )
                handler.postDelayed({
                    if (!replied.get()) {
                        locationManager.removeUpdates(listener)
                        reply(lastKnown())
                    }
                }, timeoutMs)
            }
        } catch (e: SecurityException) {
            reply(null)
        }
    }

    // --- Suivi continu, uniquement pendant que la carte est visible ---------
    //
    // Démarré par l'abonnement côté Dart et arrêté dès qu'il est annulé, c'est-à-dire
    // dès que l'app quitte le premier plan. Rien n'est écrit, rien n'est transmis :
    // les positions ne servent qu'à dessiner l'indicateur et à peser les gestes (§6.2).

    private var streamSink: EventChannel.EventSink? = null

    private val streamListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            streamSink?.success(
                mapOf(
                    "lat" to location.latitude,
                    "lng" to location.longitude,
                    "accuracy" to location.accuracy.toDouble(),
                ),
            )
        }

        @Deprecated("Requis par l'interface sur les API < 29")
        override fun onStatusChanged(p: String?, s: Int, e: Bundle?) = Unit

        override fun onProviderEnabled(provider: String) = Unit
        override fun onProviderDisabled(provider: String) = Unit
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        streamSink = events
        // Sans permission on ne renvoie pas d'erreur : l'abonnement reste en
        // place, prêt à être réarmé par `onRequestPermissionsResult`. Une erreur
        // ferait fermer le flux côté Flutter, et il n'y aurait plus rien à
        // réarmer.
        startUpdates()
    }

    /**
     * Démarre — ou redémarre — les mises à jour de position vers le flux.
     *
     * Ne fait rien sans permission ni service de localisation, et se contente de
     * se réenregistrer si elle est rappelée : `removeUpdates` d'abord évite
     * d'empiler deux abonnements sur le même écouteur.
     */
    private fun startUpdates() {
        if (streamSink == null || !hasPermission() || !isLocationEnabled()) return

        // Le dernier point connu part tout de suite : l'indicateur s'affiche sans
        // attendre le premier fix, qui peut prendre une dizaine de secondes.
        lastKnown()?.let { streamListener.onLocationChanged(it) }

        try {
            locationManager.removeUpdates(streamListener)
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (locationManager.isProviderEnabled(provider)) {
                    locationManager.requestLocationUpdates(
                        provider,
                        UPDATE_INTERVAL_MS,
                        UPDATE_DISTANCE_M,
                        streamListener,
                        Looper.getMainLooper(),
                    )
                }
            }
        } catch (e: SecurityException) {
            // Permission retirée entre-temps : l'indicateur s'arrête, l'app
            // continue de fonctionner sans (§11.1).
        }
    }

    override fun onCancel(arguments: Any?) {
        try {
            locationManager.removeUpdates(streamListener)
        } catch (e: SecurityException) {
            // Rien à arrêter.
        }
        streamSink = null
    }

    /** Dernier point connu : mieux que rien quand le capteur met trop longtemps. */
    private fun lastKnown(): Location? = try {
        listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { locationManager.getLastKnownLocation(it) }
            .maxByOrNull { it.time }
    } catch (e: SecurityException) {
        null
    }
}
