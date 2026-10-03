package me.safe

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.os.SystemClock
import android.util.Log
import java.io.File

/**
 * Oubli des traces de localisation laissées sur l'appareil (§11.1).
 *
 * Exigence : quelqu'un qui volerait le téléphone et obtiendrait un accès complet
 * à son contenu ne doit y trouver aucune trace de plus d'une heure de l'endroit
 * où l'appareil est passé.
 *
 * Aucun de ces fichiers ne contient de position GPS — les fixes vivent en
 * mémoire et ne sont jamais écrits. Ce qu'ils disent, c'est « cette zone a été
 * regardée », ce qui revient au même en pratique :
 *
 *  - `mbgl-offline.db`, table `tiles` : les tuiles du fond de carte, avec leur
 *    z/x/y et leur heure d'accès. C'est la trace la plus fine — une tuile de
 *    niveau 15 fait 1,2 km de côté.
 *  - `app.sqlite`, table `cached_areas` : les rectangles déjà chargés.
 *  - `app.sqlite`, table `cached_hazards` : les dangers de ces rectangles.
 *
 * **Pourquoi en Kotlin plutôt qu'en Dart.** Rien de Flutter ne tourne pendant
 * que l'app est en arrière-plan. Regarder la carte puis empocher le téléphone
 * laisserait la trace intacte jusqu'à la prochaine ouverture, c'est-à-dire
 * potentiellement des jours. Une alarme système réveille le processus même
 * après qu'Android l'a tué.
 *
 * **Pourquoi du SQL direct plutôt que `clearAmbientCache()`.** La fonction du
 * plugin efface tout ou rien : appelée en pleine sortie, elle rendrait la carte
 * blanche au moment précis où on roule dessus. Ici la coupure se fait à l'âge,
 * la vue en cours survit, et les tuiles d'une zone téléchargée volontairement
 * sont épargnées — une zone est une trace que la personne a créée exprès et
 * qu'elle voit listée (voir `OfflineMapsSheet`).
 */
object TraceSweeper {
    /**
     * Âge au-delà duquel une trace est effacée pendant que l'app est à l'écran.
     *
     * Une purge à l'âge plutôt qu'en bloc : la vue qu'on est en train de lire
     * survit, seul le passé s'efface.
     */
    const val MAX_TRACE_AGE_MS = 45L * 60L * 1000L

    /**
     * Délai de l'alarme, comptée depuis le passage en arrière-plan.
     *
     * Quand elle se déclenche, elle n'efface pas à l'âge : elle efface **tout**
     * ce qui n'appartient pas à une zone téléchargée. Vingt minutes sans
     * regarder la carte, et il ne reste rien.
     *
     * C'est ce qui rend le plafond calculable, et pas seulement espéré :
     *
     *     45 min (âge toléré au premier plan)
     *   +  5 min (intervalle entre deux passages, côté Flutter)
     *   + 20 min (délai de l'alarme)
     *   + 15 min (fenêtre de report qu'Android s'accorde, 75 % du délai —
     *             mesuré : 33 min 45 s pour une alarme à 45 min)
     *   = 85 min au pire, d'où l'annonce « au plus tard une heure et demie ».
     *
     * L'alarme est inexacte : `setExactAndAllowWhileIdle` demanderait
     * `SCHEDULE_EXACT_ALARM`, que la personne doit accorder à la main dans les
     * réglages, ou `USE_EXACT_ALARM`, réservée aux réveils et minuteurs. Aucune
     * des deux n'est honnête ici. Le quota d'alarmes par « bucket » de veille
     * ne mord pas : elle est toujours programmée juste après un usage actif,
     * donc l'app est au mieux de son classement.
     */
    const val ALARM_DELAY_MS = 20L * 60L * 1000L

    private const val TAG = "TraceSweeper"
    private const val ALARM_REQUEST = 1

    /**
     * Efface les traces plus vieilles que [maxAgeMs]. Zéro efface tout ce qui
     * n'appartient pas à une zone téléchargée. Rend le nombre de lignes
     * supprimées, pour les journaux de mise au point.
     */
    fun sweep(context: Context, maxAgeMs: Long = MAX_TRACE_AGE_MS): Int {
        val cutoff = (System.currentTimeMillis() - maxAgeMs) / 1000
        val removed = sweepTiles(context, cutoff) + sweepHazardCache(context, cutoff)
        Log.i(TAG, "purge des traces : $removed lignes (âge > ${maxAgeMs / 60000} min)")
        return removed
    }

    /** Arme l'alarme. Appelé quand l'app passe en arrière-plan. */
    fun schedule(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + ALARM_DELAY_MS,
            alarmIntent(context),
        )
    }

    /**
     * Désarme l'alarme. Appelé au retour au premier plan : sans cela elle
     * viderait le cache sous les yeux de quelqu'un en train de lire la carte.
     */
    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarmIntent(context))
    }

    private fun alarmIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            Intent(context, TraceSweepReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun sweepTiles(context: Context, cutoffSeconds: Long): Int =
        withDatabase(File(context.filesDir, "mbgl-offline.db")) { db ->
            db.delete(
                "tiles",
                "accessed < ? AND id NOT IN (SELECT tile_id FROM region_tiles)",
                arrayOf(cutoffSeconds.toString()),
            )
        }

    private fun sweepHazardCache(context: Context, cutoffSeconds: Long): Int =
        withDatabase(File(context.filesDir, "app.sqlite")) { db ->
            val age = arrayOf(cutoffSeconds.toString())
            db.delete("cached_areas", "fetched_at < ?", age) +
                db.delete("cached_hazards", "cached_at < ?", age)
        }

    /**
     * Le fichier peut ne pas exister (premier lancement), et MapLibre peut
     * l'avoir ouvert en même temps — SQLite gère les deux connexions, mais une
     * purge ratée ne doit jamais faire tomber l'app.
     */
    private fun withDatabase(file: File, body: (SQLiteDatabase) -> Int): Int {
        if (!file.exists()) return 0
        return try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                // Sans cela SQLite se contente de marquer les pages libres : le
                // contenu effacé reste lisible dans le fichier, et la purge
                // n'est que cosmétique devant quelqu'un qui sait lire un disque.
                //
                // `rawQuery` et non `execSQL` : ce PRAGMA rend une valeur, et
                // `execSQL` refuse tout ce qui ressemble à une lecture.
                db.rawQuery("PRAGMA secure_delete = ON", null).use { it.moveToFirst() }
                body(db)
            }
        } catch (e: SQLiteException) {
            Log.w(TAG, "purge impossible sur ${file.name}", e)
            0
        }
    }
}

/**
 * Réveil de l'alarme : le processus peut avoir été tué entre-temps.
 *
 * Elle efface tout, sans regarder l'âge. Personne ne lit la carte à ce
 * moment-là, et c'est ce qui borne le pire cas : sans quoi, ce que l'alarme
 * épargnerait faute d'être assez vieux ne serait jamais repris par personne.
 */
class TraceSweepReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TraceSweeper.sweep(context, maxAgeMs = 0L)
    }
}
