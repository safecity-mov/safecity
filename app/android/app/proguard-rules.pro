# L'application — règles R8 du build release.
#
# Le build de debug ne passe pas par R8 : ce fichier n'a donc d'effet qu'au moment de
# publier, et son absence ne se voit nulle part avant (SPEC §12.6, §14 semaine 7).
#
# maplibre_gl embarque un moteur de localisation qui passe par les Google Play Services.
# Le projet les exclut de l'arbre de build — `configurations.all { exclude(group =
# "com.google.android.gms") }` dans build.gradle.kts — parce que F-Droid refuse les
# dépendances propriétaires, et qu'il ne suffit pas de ne pas les appeler : elles ne
# doivent pas être dans le binaire du tout.
#
# Les classes disparaissent, mais les références que le bytecode de MapLibre porte vers
# elles restent. R8 refuse alors de compiler, et il a raison de demander : une référence
# non résolue est d'ordinaire un oubli. Ici c'est le résultat voulu.
#
# Ce code n'est jamais atteint à l'exécution. La carte est construite avec
# `myLocationEnabled: false`, donc le LocationComponent de MapLibre — le seul à instancier
# ce moteur — n'est jamais activé. La position vient de LocationChannel.kt, qui parle
# directement au LocationManager d'Android.
#
# La liste est **nominative, et pas `com.google.android.gms.**`**. C'est le même garde-fou
# que l'exclusion Gradle : le jour où une dépendance transitive amène une référence à une
# autre classe GMS, le build casse et on le voit, au lieu de la laisser passer en silence.
-dontwarn com.google.android.gms.common.GoogleApiAvailability
-dontwarn com.google.android.gms.location.FusedLocationProviderClient
-dontwarn com.google.android.gms.location.LocationCallback
-dontwarn com.google.android.gms.location.LocationRequest
-dontwarn com.google.android.gms.location.LocationRequest$Builder
-dontwarn com.google.android.gms.location.LocationServices
-dontwarn com.google.android.gms.tasks.OnFailureListener
-dontwarn com.google.android.gms.tasks.OnSuccessListener
-dontwarn com.google.android.gms.tasks.Task
