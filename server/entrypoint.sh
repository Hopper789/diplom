#!/bin/bash
set -e

echo "Configuring Apache..."

echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null 2>&1 || true

a2enmod cgi >/dev/null 2>&1 || true
a2enmod headers >/dev/null 2>&1 || true

rm -f /etc/apache2/sites-enabled/*.stale.*.conf || true

HTTPD_CONF="$(
    find /project -maxdepth 2 -type f -name '*.httpd.conf' ! -path '*/*.stale.*/*' 2>/dev/null \
        | sort \
        | head -n1 || true
)"

if [[ -n "$HTTPD_CONF" && -f "$HTTPD_CONF" ]]; then
    PROJECT_DIR="$(dirname "$HTTPD_CONF")"
    PROJECT_NAME="$(basename "$PROJECT_DIR")"

    echo "BOINC project found: $PROJECT_DIR"
    echo "Enabling Apache config..."

    cp "$HTTPD_CONF" "/etc/apache2/sites-enabled/${PROJECT_NAME}.conf"

    chmod a+rx /project || true
    chmod a+rx "$PROJECT_DIR" || true

    chmod -R a+rX "$PROJECT_DIR/html" || true
    chmod -R a+rX "$PROJECT_DIR/cgi-bin" || true
    chmod -R a+rX "$PROJECT_DIR/download" || true

    # BOINC scheduler/handlers run under Apache user; ensure writable dirs.
    for d in "$PROJECT_DIR/log_boinc-server" "$PROJECT_DIR/upload" "$PROJECT_DIR/tmp_boinc-server" "$PROJECT_DIR/html/cache"; do
        if [[ -d "$d" ]]; then
            chown -R www-data:www-data "$d" || true
            chmod -R u+rwX,go+rX "$d" || true
        fi
    done

    echo "Fixing BOINC config hostname..."
    if [[ -f "$PROJECT_DIR/config.xml" ]]; then
        sed -i "s/<host>.*<\\/host>/<host>$(hostname)<\\/host>/g" "$PROJECT_DIR/config.xml"
        python3 - "$PROJECT_DIR/config.xml" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def set_tag(body: str, tag: str, value: str) -> str:
    pattern = rf"<{tag}>.*?</{tag}>"
    replacement = f"<{tag}>{value}</{tag}>"
    if re.search(pattern, body, flags=re.S):
        return re.sub(pattern, replacement, body, flags=re.S)
    return body.replace("</config>", f"        {replacement}\n    </config>")

text = set_tag(text, "max_wus_to_send", "1")
text = set_tag(text, "min_sendwork_interval", "1")
path.write_text(text, encoding="utf-8")
PY
    fi

    echo "Starting BOINC project daemons..."
    cd "$PROJECT_DIR"
    ./bin/start || true
else
    echo "BOINC project config not found yet. Create project first."
fi

apachectl configtest

# On container restart Apache pidfile may become stale; ensure a clean foreground start.
rm -f /var/run/apache2/apache2.pid /run/apache2/apache2.pid || true
pkill -9 apache2 >/dev/null 2>&1 || true

exec apache2ctl -D FOREGROUND
