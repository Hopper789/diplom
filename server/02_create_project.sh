#!/usr/bin/env bash
echo Creating project...
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

mkdir -p "$BOINC_PROJECTS_DIR"

echo "[1/5] Creating database and DB user..."
sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "[2/5] Creating BOINC project..."
cd "$BOINC_SRC_DIR/tools"

if [ ! -d "$BOINC_PROJECTS_DIR/$PROJECT_NAME" ]; then
  ./make_project \
    --url_base "$PROJECT_URL" \
    --db_name "$DB_NAME" \
    --db_user "$DB_USER" \
    --db_passwd "$DB_PASSWORD" \
    --project_root "$BOINC_PROJECTS_DIR/$PROJECT_NAME" \
    "$PROJECT_NAME"
else
  echo "Project already exists: $BOINC_PROJECTS_DIR/$PROJECT_NAME"
fi

echo "[3/5] Setting permissions..."
sudo chown -R "$USER":www-data "$BOINC_PROJECTS_DIR/$PROJECT_NAME"
sudo chmod -R g+w "$BOINC_PROJECTS_DIR/$PROJECT_NAME"

echo "[4/5] Apache configuration reminder..."
echo "Check generated Apache config inside:"
echo "$BOINC_PROJECTS_DIR/$PROJECT_NAME/${PROJECT_NAME}.httpd.conf"
echo
echo "Usually you need to link it manually, for example:"
echo "sudo ln -s $BOINC_PROJECTS_DIR/$PROJECT_NAME/${PROJECT_NAME}.httpd.conf /etc/apache2/sites-enabled/${PROJECT_NAME}.conf"
echo "sudo systemctl reload apache2"

echo "[5/5] Starting BOINC project daemons..."
cd "$BOINC_PROJECTS_DIR/$PROJECT_NAME"
./bin/start

echo "Project created."
echo "Open project URL: $PROJECT_URL"
echo "Then create a user account and paste ACCOUNT_KEY into config.env."