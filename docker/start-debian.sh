#!/bin/sh

env >> /etc/default/locale

if [ -n "$ENCRYPTION_PUB_KEY" ];then
	echo "$ENCRYPTION_PUB_KEY" | gpg --import
fi

service cron start

sh /start.sh
