# Backupable

Backupable نسخه نگه‌داری‌شده‌ای از پروژه `erfjab/Backuper` است. این ابزار از سرور بکاپ زمان‌بندی‌شده می‌گیرد و فایل‌ها را از طریق Telegram، Discord یا Gmail ارسال می‌کند.

پشتیبانی از Remnawave به‌صورت مستقیم وجود دارد و برای Telegram و Discord می‌توان HTTP/SOCKS proxy تنظیم کرد.

## امکانات

- زمان‌بندی قابل تنظیم;
- ارسال از طریق Telegram، Discord و Gmail;
- پشتیبانی از HTTP/SOCKS proxy برای Telegram و Discord;
- پشتیبانی از Telegram topic;
- تقسیم فایل برای محدودیت حجم سرویس‌ها;
- رمز اختیاری برای ZIP;
- قالب آماده برای Remnawave و چند سرویس دیگر;
- جلوگیری از اجرای هم‌زمان یک job با `flock`.

## نصب

### Native

```bash
git clone https://github.com/AidarKhusainov/backupable.git
cd backupable
sudo bash backupable.sh
```

در حالت Native، jobها زیر `/root` ساخته می‌شوند و از crontab کاربر root استفاده می‌شود.

### Docker Compose

برای نصب استاندارد Docker در Remnawave می‌توانید از Compose استفاده کنید:

```bash
mkdir -p /opt/backupable
cd /opt/backupable

curl -fsSLo compose.yaml \
  https://raw.githubusercontent.com/AidarKhusainov/backupable/master/compose.yaml

docker compose pull
docker compose up -d
docker compose run --rm backupable setup
```

Docker mode scheduler داخلی دارد و به host cron نیاز ندارد.

دستورهای مفید:

```bash
docker compose exec backupable backupable status
docker compose exec backupable backupable backup-now
docker compose logs -f backupable
```

Image رسمی پروژه:

`ghcr.io/aidarkhusainov/backupable:latest`

Docker mode مسیر `/opt/remnawave` را read-only mount می‌کند و برای اجرای `pg_dump` داخل کانتینر `remnawave-db` به `/var/run/docker.sock` دسترسی دارد. این دسترسی عملاً سطح دسترسی root روی Docker host می‌دهد.

## Remnawave

قالب Remnawave برای deployment استاندارد در نظر گرفته شده است:

- مسیر `/opt/remnawave`;
- کانتینر PostgreSQL با نام `remnawave-db`.

هر بکاپ شامل فایل‌های کامل `/opt/remnawave` و dump دیتابیس PostgreSQL است.

## امنیت

- فایل‌های job و state فقط برای root قابل دسترسی هستند.
- token، webhook، proxy URL، فایل `.env` و اطلاعات دیتابیس را در issue عمومی منتشر نکنید.
- پسورد ZIP جایگزین encryption مدرن نیست.
- فقط گرفتن بکاپ کافی نیست؛ restore را هم تست کنید.
- Docker mode به Docker socket دسترسی دارد و در عمل دسترسی root-equivalent به host دارد.

## مجوز

پروژه تحت [MIT License](LICENSE) منتشر می‌شود.

پروژه اصلی: `erfjab/Backuper`.

نگه‌داری فعلی: AidarKhusainov.
