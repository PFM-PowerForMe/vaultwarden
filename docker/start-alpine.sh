#!/bin/sh

env >> /etc/default/locale

crond

sh /start.sh