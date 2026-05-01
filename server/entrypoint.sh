#!/bin/bash
set -e

echo "Configuring Apache..."

echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null 2>&1 || true

a2enmod cgi >/dev/null 2>&1 || true
a2enmod headers >/dev/null 2>&1 || true

if [ -f /project/my_project/my_project.httpd.conf ]; then
    echo "BOINC project found. Enabling Apache config..."

    cp /project/my_project/my_project.httpd.conf /etc/apache2/sites-enabled/my_project.conf

    chmod a+rx /project || true
    chmod a+rx /project/my_project || true

    chmod -R a+rX /project/my_project/html || true
    chmod -R a+rX /project/my_project/cgi-bin || true
    chmod -R a+rX /project/my_project/download || true

    echo "Fixing BOINC config hostname..."
    if [ -f /project/my_project/config.xml ]; then
        sed -i "s/<host>.*<\/host>/<host>$(hostname)<\/host>/g" /project/my_project/config.xml
    fi

    echo "Starting BOINC project daemons..."
    cd /project/my_project
    ./bin/start || true
else
    echo "BOINC project config not found yet. Create project first."
fi

apachectl configtest

exec apachectl -D FOREGROUND