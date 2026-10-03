# Vie privée

*Écrit pour être lu par la personne qui installe l'application, pas par un juriste. Chaque phrase
correspond à quelque chose de vérifiable dans le code : les renvois en fin de page disent où.*

*Version 0 — 14 septembre 2026. Bêta fermée.*

---

## L'essentiel en six phrases

1. **Il n'y a pas de compte.** Votre téléphone tire un numéro au hasard à la première ouverture.
   C'est votre seule identité, et vous pouvez la jeter quand vous voulez.
2. **Votre position ne quitte jamais votre téléphone.** Quand vous signalez un danger,
   l'application regarde elle-même à quelle distance vous en êtes et n'envoie que « sur place »
   ou « ailleurs ». Le serveur ne reçoit pas vos coordonnées : il n'a rien à en oublier.
3. **Ce que vous regardez sur la carte est effacé de votre téléphone au bout d'une heure et
   demie au plus tard.**
4. **Le lien entre votre téléphone et vos signalements est coupé au bout de 24 heures.** Passé
   ce délai, plus rien ne dit que c'est vous.
5. **Aucune mesure d'audience, aucun traceur, aucun service tiers.** L'application ne contacte
   qu'un seul serveur, le nôtre.
6. **Ce que vous écrivez dans un commentaire est public et définitif.** C'est la seule chose ici
   dont vous devez vous méfier.

---

## Ce que nous savons de vous

Un **numéro tiré au hasard**, du genre `9f1c8a3e-…`, fabriqué par votre téléphone et gardé sur
lui, chiffré. Il ne vient d'aucun catalogue, il ne ressemble à aucun autre identifiant de votre
appareil, et il ne suit rien en dehors de l'application. Il sert à deux choses : vous empêcher de
voter deux fois sur le même danger, et vous laisser retirer votre propre signalement dans les
24 heures.

Vous pouvez en changer à tout moment, dans les paramètres. Cela coupe le lien avec tout ce que
vous avez fait avant, immédiatement, sans rien demander à personne. Désinstaller l'application
le détruit aussi : il n'est sauvegardé nulle part, pas même sur votre compte Google.

**Nous ne vous demandons jamais** de nom, d'adresse e-mail, de numéro de téléphone. Il n'existe
aucun champ pour les saisir. Nous ne lisons ni votre carnet d'adresses, ni votre calendrier, ni
votre identifiant publicitaire. L'application ne demande que trois autorisations : Internet, et
la localisation — fine et approximative.

Nous ne conservons **aucun journal de connexion**. Ni votre adresse IP, ni l'heure de vos
requêtes ne sont écrites où que ce soit. Une seule exception, qui ne concerne pas l'application
mais notre page de téléchargement : quand quelqu'un y télécharge le fichier d'installation, nous
notons **le jour et l'heure, le nom du fichier, et la langue que son navigateur annonce**, par
exemple « fr-FR ». C'est ce qui nous permet de savoir si la bêta est téléchargée, et d'où à peu
près. Nous ne notons pas l'adresse IP : elle n'est ni écrite, ni convertie en lieu. Ce journal
s'arrête à la page ; l'application elle-même ne laisse aucune trace de ce genre.

Le serveur refuse aussi les demandes trop nombreuses venant d'une même adresse, pour rester
disponible devant un programme qui le bombarderait. Il compte ces demandes en mémoire, sur la
minute qui court, puis oublie. Quand il en refuse une, il note **le jour, l'heure et le chemin
demandé**, jamais l'adresse : nous savons que la limite a servi, pas à qui.

## Ce que nous enregistrons, et pourquoi c'est le minimum

Un signalement, c'est un fait sur la voirie : un nid-de-poule à tel endroit, de tel niveau, à
telle heure. **L'endroit et l'heure sont conservés au mètre et à la seconde près**, sans arrondi.
Un trou localisé « à cinquante mètres près » ne sert à personne, et dégrader cette précision
serait une fausse protection de la vie privée : elle abîmerait le produit sans rien vous
protéger, puisque c'est le trou qu'elle décrit, pas vous.

Ce qui vous concerne, c'est le **lien** entre ces faits. C'est lui que nous bornons.

| Ce qui est enregistré | Pourquoi | Pendant combien de temps |
|---|---|---|
| L'endroit du danger, son niveau, son type | C'est le service | Vie du signalement |
| L'heure de chaque geste | Ancienneté, ordre des événements | Vie du signalement |
| « sur place / ailleurs » | Un geste fait sur place pèse plus qu'un geste fait de loin | Vie du geste |
| Votre numéro, attaché à vos gestes | Anti-double-vote, retrait sous 24 h | **24 heures** |
| Votre commentaire, si vous en écrivez un | Préciser le danger | Vie du signalement |

Au bout de 24 heures, votre numéro est retiré de tout : de vos gestes, et de vos signalements.
Les signalements restent — ce sont des données sur la voirie, pas sur vous — mais plus rien ne
permet de dire qu'ils viennent du même téléphone, donc plus rien ne redessine vos trajets
habituels. C'est le cœur de ce document : **nous ne cachons pas les faits, nous coupons ce qui
les relie à vous.**

## Votre position

Elle ne quitte pas votre téléphone. Pas « elle est effacée après » : elle ne part pas.

Un geste pèse d'autant plus que vous êtes près du danger. Le calcul se fait donc sur votre
appareil : l'application compare votre position à celle du danger et n'envoie qu'une valeur
parmi deux — « sur place », à moins de 100 mètres, ou « ailleurs, ou position inconnue ». C'est
tout ce que le serveur reçoit, et c'est tout ce qu'il écrit. Il n'existe d'ailleurs dans la
base aucune colonne où vos coordonnées pourraient être rangées.

Ce n'était pas le cas jusqu'en septembre 2026 : vos coordonnées partaient dans la requête, le
serveur en tirait la même valeur et les jetait. Elles n'étaient pas enregistrées, mais il
fallait nous croire sur la suite. Maintenant il n'y a plus rien à croire : elles ne sortent
pas.

Les seuils, eux, viennent du serveur — sans quoi deux versions de l'application installées en
même temps ne compteraient pas pareil.

Pendant que la carte est affichée, l'application suit votre position pour dessiner le point
bleu. Ce suivi s'arrête dès que vous quittez l'application, la position n'est jamais écrite sur
le disque, et **aucune autorisation d'arrière-plan n'est demandée** : l'application ne peut
techniquement pas vous suivre quand elle n'est pas à l'écran.

Refuser la localisation reste un usage normal : vous pouvez signaler un danger en le pointant
sur la carte. Votre geste comptera simplement un peu moins qu'un geste fait sur place.

## Ce que votre téléphone garde, et pendant une heure et demie au plus

Afficher une carte laisse des traces d'une autre nature que le GPS : pour ne pas retélécharger
sans cesse les mêmes images, l'application garde un moment les morceaux de carte que vous avez
regardés, et les dangers qui s'y trouvent. Mis bout à bout, cela dit où vous êtes passé.

**Pendant que vous regardez la carte, rien n'y dépasse 45 minutes.** Et vingt minutes après que
vous l'avez quittée, tout est effacé — y compris quand l'application est fermée et que le
téléphone est dans votre poche : une alarme du système réveille l'application pour faire le ménage.
L'effacement est réel, les octets sont écrasés et pas seulement oubliés.

Android se réserve le droit de retarder un peu cette alarme pour économiser la batterie. C'est
pourquoi nous annonçons **une heure et demie** : c'est le plafond, retard maximal compris. Dans
les faits, sur nos essais, l'alarme arrive à deux minutes près.

Conséquence : si vous rouvrez l'application sans réseau une heure après, la carte sera vide et
vous le dira franchement. Nous préférons une carte qui avoue ne rien savoir à une carte propre
qui laisse croire qu'il n'y a pas de danger.

**Une exception, et elle est de votre fait** : si vous téléchargez une zone pour l'avoir hors
connexion, cette zone reste sur votre téléphone jusqu'à ce que vous la supprimiez. Elle
apparaît dans la liste, avec un bouton pour l'effacer.

Ce sont les **rues** qui sont embarquées, pas les dangers. Un danger, pris à part, ne dit rien
de vous : c'est un fait sur la voirie, le même pour tout le monde. Mais la liste de ceux que
votre téléphone a chargés dessine les endroits où vous êtes passé, exactement comme les
morceaux de carte. Les deux s'effacent donc ensemble, dans le même délai. Une zone
téléchargée vous montrera les rues sans réseau, et vous dira qu'elle ne sait rien des dangers.

Enfin, Android photographie l'écran de chaque application pour son écran « applications
récentes » — dans notre cas, une carte centrée sur l'endroit où vous étiez. L'application refuse
cette photo.

## Pas de photos

L'application ne permet pas d'ajouter de photo, et n'en demandera pas pendant la bêta. Une photo de
rue contient souvent plus que la rue — un visage, une plaque, une façade reconnaissable — et les
fichiers eux-mêmes emportent la position et le numéro de série de l'appareil. Tant que nous
n'avons pas de quoi nettoyer et modérer tout cela correctement, il n'y en aura pas.

## Vos droits, et comment les exercer sans nous écrire

Dans les paramètres de l'application, sans justification et sans délai :

- **Retirer mes signalements récents** — tout ce que vous avez signalé depuis 24 heures quitte
  la carte, d'un coup. Pour qui a fait des essais, ou s'est trompé. Au-delà de 24 heures, le
  serveur ne sait plus lesquels sont les vôtres : personne ne peut plus les retirer, vous
  compris. C'est le revers de la promesse du point 4.
- **Effacer mes données** — votre numéro disparaît de tous vos gestes sur le serveur, vos votes
  cessent de compter, et votre téléphone tire un numéro neuf, sans lien avec le précédent. Si le serveur est injoignable à ce
  moment-là, le téléphone change quand même de numéro, et le lien avec l'ancien s'efface tout
  seul sous 24 heures.

Vos signalements, eux, restent sur la carte. Ils décrivent l'état d'une rue, et d'autres
usagers s'appuient dessus. Après effacement, plus rien n'indique qu'ils viennent de vous.

Si vous voulez la disparition complète d'un signalement — une erreur, une photo malheureuse —
écrivez-nous : c'est le seul cas qui passe par une intervention humaine.

## Qui héberge, qui répond

Tout tourne sur **un seul serveur, que nous administrons**. Le fond de carte et la
recherche d'adresse sont hébergés là aussi : l'application ne contacte aucun autre domaine, pas
même pour afficher la carte. Il n'y a **aucun sous-traitant**, aucune dépendance à Google — pas
même les services de localisation de Google, remplacés par ceux d'Android.

À chaque ouverture, à chaque retour au premier plan et quand vous ouvrez les paramètres,
l'application demande à ce même serveur quelle est la **dernière version** publiée, pour vous
prévenir si la vôtre est en retard, relit le catalogue des types de danger, et regarde si
l'équipe a une **annonce** à faire — une ligne, la même pour tout le monde, écrite depuis la
console d'administration, par exemple pour vous prévenir d'une panne. Ces demandes ne
contiennent rien : ni votre numéro, ni la version que vous utilisez, ni quoi que ce soit
d'autre — c'est la même requête pour tout le monde, et le serveur n'en garde pas trace. Si une
version plus récente existe, un bandeau vous le dit ; c'est vous qui décidez de la télécharger.
Une annonce s'affiche de la même façon, et se ferme d'un toucher ; l'application retient
seulement, sur votre téléphone, le numéro de la dernière annonce que vous avez fermée, pour
ne pas vous la remontrer.

Base légale : intérêt légitime. Pendant la bêta fermée, le responsable de traitement est
l'éditeur du logiciel ; une association loi 1901 sera constituée avant toute ouverture au
public.

Le code du serveur et de l'application est public. Ce document décrit ce que le code fait, et
le code est là pour être vérifié par qui veut.

## Ce qui changera

Ce texte est daté. Toute modification sera visible dans l'historique public du dépôt, et une
version qui réduirait vos protections vous sera signalée dans l'application, pas glissée
discrètement.

---

### Où vérifier, dans le code

| Affirmation | Où |
|---|---|
| Un numéro au hasard, en stockage chiffré | `app/lib/src/data/device_identity.dart` |
| La position devient deux valeurs sur votre appareil | `app/lib/src/data/proximity.dart` |
| Le serveur n'a plus de quoi recevoir une coordonnée | `server/db/migrations/0100_local_proximity.sql` |
| Aucune colonne ne peut recevoir votre position | `server/db/migrations/0010_enums_tables.sql` |
| Le lien est coupé à 24 heures | `server/db/migrations/0050_privacy_retention.sql` |
| Les traces de carte sont effacées au plus tard à une heure et demie | `app/android/app/src/main/kotlin/me/safe/TraceSweeper.kt` |
| Aucun journal d'accès, sauf celui des téléchargements de l'APK et celui des refus de la limitation de débit, tous deux sans adresse IP | `server/caddy/Caddyfile` (`log apk`, `log blocked`, `rate_limit`), `server/docker-compose.yml` |
| Aucune autorisation d'arrière-plan | `app/android/app/src/main/AndroidManifest.xml` |
| Pas de sauvegarde vers Google | idem, `allowBackup="false"` |
| La demande de dernière version ne porte rien, et ne renvoie que chez nous | `app/lib/src/data/app_update.dart` |
| L'API n'expose jamais qui a signalé quoi | `server/db/migrations/0060_grants_rls.sql` |

Les règles de confidentialité sont testées, pas seulement écrites :
`server/db/tests/060_privacy.sql`.
