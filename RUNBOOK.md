# RUNBOOK — self-hosted Sentry na dragonie

Aktualizacja 2026-09-08 23:40: stary stack jest WYŁĄCZONY. Decyzją Foundera
(sesja 2026-09-08, „spierdala" na datadisk Colimy) profil `default` Colimy i jego
dysk 77 GB zostały skasowane razem z wolumenami Sentry; autostart `homebrew.mxcl.colima`
zatrzymany, agent `io.vetcoders.sentry-stack-watchdog` wyładowany (plist zostaje).
Telemetria żyje w GlitchTipie na libraxis-vm — patrz
[migration/glitchtip/README.md](migration/glitchtip/README.md), sekcja „Deployed".
Poniższy opis operacyjny jest historyczny.

Stan na 2026-08-26. Deployment postawiony 2026-04-21 (26.4.0), zmigrowany
2026-04-28 na nightly `26.5.0.dev0+c5b6ba87` (obraz z 2026-04-28). Dane żyją
w wolumenach Dockera wewnątrz VM Colima — przeżywają `docker compose down`
i restart Colimy. NIE przeżyją `docker volume rm` ani `colima delete`.

## Co gdzie działa

| Rzecz | Wartość |
|---|---|
| URL lokalny | `http://127.0.0.1:9000` (nginx publikuje 9000 na 0.0.0.0 — widoczny też w LAN) |
| URL publiczny | `https://sentry.vistavet.app` (DNS → 213.160.77.173 → proxy → dragon → nginx:9000) |
| Runtime | Colima (profil `default`), 8 CPU / 64 GB RAM / 100 GB dysk, Docker Compose, 72 serwisy, profil `feature-complete` |
| Konta admin | `m.gad@amlt.ai`, `hello@vetcoders.io` (oba superuser) |
| Organizacja / projekty | org `sentry`: internal(1), vista-portal-be(2), vista-portal-fe(3), vista-desktop(4), lbrx-services(5), vista-brain(6) |
| Sekrety | `sentry/config.yml` (system.secret-key), `relay/credentials.json`, `.env.custom` (SMTP Resend) — wszystkie gitignored, nie commitować |
| Mail | SMTP Resend przez `.env.custom`, wpinany do `web` i `taskworker` przez `docker-compose.override.yml` (env_file) |
| Retencja eventów | 90 dni (`SENTRY_EVENT_RETENTION_DAYS`), cleanup cron w kontenerach |

## Start / stop / restart

```bash
cd ~/Libraxis/02-self-hosted/Sentry-Selfhosted

docker compose up --wait      # start (2–4 min do pełnego healthy)
docker compose restart web    # restart pojedynczego serwisu
docker compose stop           # stop bez kasowania kontenerów
docker compose down           # kasuje kontenery, ZOSTAWIA wolumeny z danymi
./scripts/vc-smoke.sh         # weryfikacja: kontenery + health + postgres + dysk
```

Restart policy wszystkich serwisów to `unless-stopped` — po restarcie samego
Dockera/Colimy stack wstaje sam. Po reboocie maca Colimę startuje launchd
(`brew services` → `homebrew.mxcl.colima`, włączone 2026-08-26); jeśli po
reboocie stack nie żyje: `brew services start colima && docker compose up --wait`.

## Backup

Metadane (users, orgi, projekty, DSN-y, alerty — bez eventów):

```bash
./sentry-admin.sh export global /path/backup.json   # lub ./scripts/backup.sh global
```

Pełny backup danych (eventy w ClickHouse + Postgres): zatrzymaj stack
(`docker compose stop`), zrób snapshot wolumenów:

```bash
for v in sentry-postgres sentry-clickhouse sentry-data sentry-kafka sentry-redis sentry-seaweedfs; do
  docker run --rm -v $v:/from -v "$PWD/backups:/to" ubuntu:24.04 \
    tar czf /to/$v-$(date +%Y%m%d).tar.gz -C /from .
done
docker compose up --wait
```

Restore metadanych: `./sentry-admin.sh import global /path/backup.json`.
Restore wolumenów: analogiczny `tar xzf` do świeżego wolumenu przy zatrzymanym stacku.
Stan 2026-08-26: **żaden regularny backup nie jest skonfigurowany** — do zrobienia.

## Update

Deployment jest na gałęzi `master` (nightly) — to działa, ale release'y są
bezpieczniejsze. Ścieżka na oficjalne 26.5.0 (nowsze niż działający nightly):

```bash
./sentry-admin.sh export global pre-upgrade.json   # backup najpierw
git fetch upstream && git checkout 26.5.0
/opt/homebrew/bin/bash ./install.sh --skip-user-creation --no-report-self-hosted-issues
docker compose up --wait && ./scripts/vc-smoke.sh
```

Uwaga: `install.sh` wymaga bash ≥ 4.4 — na macOS zawsze przez brew bash,
nigdy systemowy `/bin/bash` (3.2).

## Rollback

Migracje Postgres/ClickHouse są jednokierunkowe — **rollbacku wersji w dół nie
ma**. Jedyny prawdziwy rollback to przywrócenie snapshotu wolumenów sprzed
upgrade'u (sekcja Backup). Dlatego: żadnego `install.sh` bez wcześniejszego
exportu + (przy dużych skokach) snapshotu wolumenów.

## Dysk

Wolumeny żyją w VM Colima (`/var/lib/docker`, 98 GB). Przy ≥85%:

```bash
colima ssh -- df -h /var/lib/docker   # pomiar
docker image prune -f                 # bezpieczne: tylko dangling
docker image prune -a -f              # agresywne: skasuje też stare tagi (26.4.0)
```

**Nigdy `docker volume prune`** — przy zatrzymanym stacku wszystkie wolumeny
Sentry wyglądają na „unused" i zostałyby skasowane razem z danymi.
Powiększenie dysku VM: edytuj `~/.colima/default/colima.yaml` (`disk:`),
potem `colima stop && colima start` (downtime kilka minut, dane zostają).

## Znany failure mode: konsumery Kafki w restart-loopie po długim downtime

Objaw: `docker compose ps` pokazuje `Restarting` na serwisach `*-consumer`,
w logach `arroyo.errors.OffsetOutOfRange`. Przyczyna: retencja Kafki usunęła
segmenty, do których wskazywały zapisane offsety grupy. Naprawa (traci tylko
dane z okresu, gdy stack leżał — one i tak nie istnieją):

```bash
docker compose stop <serwis>            # np. metrics-consumer
docker compose exec kafka kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group <grupa> --reset-offsets --to-latest --all-topics --execute
docker compose start <serwis>
```

Nazwa grupy zwykle = nazwa serwisu; listę daje
`docker compose exec kafka kafka-consumer-groups --bootstrap-server kafka:9092 --list`.
Naprawione tak 2026-08-26 dla `metrics-consumer` i `generic-metrics-consumer`.

## Znane ryzyka (2026-08-26)

1. Brak regularnych backupów — jedna kopia danych, w jednej VM, na jednym hoście.
2. Obrazy `nightly` przypięte tylko lokalnym cache — `docker compose pull`
   ściągnie NOWSZY nightly i wymusi migracje; nie robić pulla bez pełnej
   procedury update.
3. Port 9000 wystawiony na LAN bez auth na poziomie sieci (`SENTRY_BIND=9000`;
   zawężenie: `SENTRY_BIND=127.0.0.1:9000` w `.env` + `docker compose up -d nginx`).
4. Publiczny ingress zależy od zewnętrznego proxy (213.160.77.173) — jego
   konfiguracja nie jest w tym repo.

---
𝚅𝚒𝚋𝚎𝚌𝚛𝚊𝚏𝚝𝚎𝚍. with AI Agents by Vetcoders (c)2024-2026 LibraxisAI
