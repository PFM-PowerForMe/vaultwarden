#!/bin/sh

env >> /etc/default/locale

service cron start

sh /start.sh
