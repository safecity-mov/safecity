# L'application — PostgreSQL 16 + PostGIS 3.4 (§7), augmenté de pg_cron et pgTAP.
#   pg_cron : coupure du lien terminal → gestes à 24 heures (§11.2).
#   pgTAP   : tests SQL des règles de modération, exigés par le projet (§6 testé en SQL).
FROM postgis/postgis:16-3.4

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-16-cron \
      postgresql-16-pgtap \
 && rm -rf /var/lib/apt/lists/*
