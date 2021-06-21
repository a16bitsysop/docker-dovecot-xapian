#!/bin/sh
#display environment variables passed with --env
echo "\$REDIS= $REDIS"
echo "\$HOSTNAME= $HOSTNAME"
echo "\$LETSENCRPT= $LETSENCRYPT"
echo "\$RSPAMD= $RSPAMD"
echo "\$POP3PORT= $POP3PORT"
echo "\$STUNNEL= $STUNNEL"
echo "\$FETCH= $FETCH"
echo

[ -z "$REDIS" ] && echo "\$REDIS is not set, needed for auth" && exit 1

NME="dovecot-xapian"
set-timezone.sh "$NME"

cd /etc/dovecot || exit 1

if [ -n "$FETCH" ]
then
	sed "s/#fileinto/fileinto/" -i /var/vmail/sieve/global/after.sieve
fi

if [ -n "$STUNNEL" ]
then
        sed -r "s/(connect =\s).*:/\1$REDIS:/" -i /etc/stunnel/stunnel.conf
        stunnel /etc/stunnel/stunnel.conf
        REDIS="127.0.0.1"
fi

echo "Waiting for redis to load database"
_ready=""
while [ -z "$_ready" ]
do
  sleep 5s
  _reply=$(echo "PING" | nc "$REDIS" 6379)
  echo "$_reply"
  echo "$_reply" | grep "PONG" && _ready="1"
done

REDISIP=$(ping -c1 "$REDIS" | head -n1 | cut -f2 -d'(' | cut -f1 -d')')
echo "uri = redis:host=$REDISIP" > dict.uri
#  echo -e "plugin {\n  quota_clone_dict = redis:host=$REDISIP:port=6379\n}" > conf.d/quota.uri

echo "#10-auto.conf from environment variables" > conf.d/10-auto.conf

if [ -n "$HOSTNAME" ]
then
  echo "hostname = $HOSTNAME" >> conf.d/10-auto.conf
  if [ -n "$LETSENCRYPT" ]
  then
    echo "ssl_cert = </etc/letsencrypt/live/$LETSENCRYPT/fullchain.pem" >> conf.d/10-auto.conf
    echo "ssl_key = </etc/letsencrypt/live/$LETSENCRYPT/privkey.pem" >> conf.d/10-auto.conf
  fi
fi

if [ -n "$POP3PORT" ]
then
   echo "
service pop3-login {
 inet_listener pop3s-hiport {
 port = $POP3PORT
 ssl = yes
 }
}
" >> conf.d/10-auto.conf
   echo "
service pop3s-hiport {
  user = vmail
}
" >> conf.d/10-auto.conf
fi

if [ -n "$RSPAMD" ]
then
   for f in spam ham; do
   sed "s/localhost/$RSPAMD/" -i "/var/vmail/sieve/global/learn-$f.sieve"
  done
fi

openssl dhparam 1024 > /etc/ssl/dh2048.pem

post-run.sh &

chown 5000:5000 /var/vmail/mailboxes  && chmod 770 /var/vmail/mailboxes

dovecot -F
