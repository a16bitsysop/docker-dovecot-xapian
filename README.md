# docker-dovecot-xapian
Dockerfile to run [dovecot](https://www.dovecot.org) as a docker container, redis is used for userdb/passdb lookups to reduce footprint.

[![Docker Pulls](https://img.shields.io/docker/pulls/a16bitsysop/dovecot-xapian.svg?style=plastic)](https://hub.docker.com/r/a16bitsysop/dovecot-xapian/)
[![Docker Stars](https://img.shields.io/docker/stars/a16bitsysop/dovecot-xapian.svg?style=plastic)](https://hub.docker.com/r/a16bitsysop/dovecot-xapian/)
[![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/a16bitsysop/dovecot-xapian/latest?style=plastic)](https://hub.docker.com/r/a16bitsysop/dovecot-xapian/)
[![Github SHA](https://img.shields.io/badge/dynamic/json?style=plastic&color=orange&label=Github%20SHA&query=object.sha&url=https%3A%2F%2Fapi.github.com%2Frepos%2Fa16bitsysop%2Fdocker-dovecot-xapian%2Fgit%2Frefs%2Fheads%2Fmain)](https://github.com/a16bitsysop/docker-dovecot-xapian)
[![GitHub Super-Linter](https://github.com/a16bitsysop/docker-dovecot-xapian/workflows/Super-Linter/badge.svg)](https://github.com/marketplace/actions/super-linter)

It uses inet lmtp with ssl and auth, instead of sockets as running inside docker network so less dependencies.  For postfix to use lmtp with ssl it needs ```lmtp_use_tls = yes``` set in main.cf

fts-xapian is used for full text search as it will replace fts-squat.

The default storage quota is 20GB per user, quota settings can be changed with userdb extra fields see [redis keys](#redis-keys).

Mailboxes are stored in dovecot's sdbox format at /var/vmail/mailboxes, so persistent storage should be mounted there to keep the email.

## Stunnel
If the STUNNEL environment variable is set then stunnel will be started to pass
redis commands over a ssl/tls tunnel.  There needs to be a stunnel server at the
other end to receive the connection, it is different from redis native ssl support.
There should also be a file /etc/stunnel/psk.txt with the pre shared key, see
[here](https://www.stunnel.org/auth.html).

## Fetching email
If the FETCH environment variable is set then incomming email is copied into the
Fetch folder for every user, this is set to delete emails older than 7days.
Normally a service like gmail will delete all the emails it fetches, but if an
email fails its checks it will be left in the Fetch folder.

An extra fetch user needs to set up for each user wishing to do this, so you can set
a seperate strong password for this.

Set the following keys

| KEY                          | Description                                                                         | Example                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| userdb/fetch.user@example.com| Username exists check, and set home inside real user                                | redis-cli set userdb/fetch.user@example.com "{\"home\":\"/var/vmail/mailboxes/example.com/user\",\"mail\":\"sdbox:~/dbox:INBOX=~/dbox/mailboxes/Fetch/dbox-Mails\"}"|
| passdb/fetch.user@example.com| Json user password hash string                                                      | redis-cli set passdb/fetch.user@example.com "{\"password\":\"{ARGON2ID}\$argon2id\$v=19\$m=65536,t=3,p=1\$PASSWORD\$HASH\"}"|

```fetch.user@example.com``` is the username used to collect the mail from the Fetch folder and
```user@example``` is the username of the user whos ```Fetch``` folder is being collected.

An agron2id password hash can be created with ```doveadm pw -s argon2id```, all ```$``` in
the returned string need escaping with ```\``` before setting the redis key.  So change
any ```$``` to ```\$```

Best used with ```POP3PORT``` to listen on a random port if port can be changed for
fetching service.

## To import email into docker-dovecot-xapian
### On old dovecot machine
* Create a user for the reverse tunnel: ```sudo useradd SSHTUNUSER -m -s /bin/true```
* Set a password: ```sudo passwd SSHTUNUSER```
* Edit /etc/ssh/sshd_config to disable login and allow tunnel:
```bash
  Match User SSHTUNUSER
  PermitOpen 127.0.0.1:2222
  X11Forwarding no
  AllowAgentForwarding no
  ForceCommand /bin/false
```
* Reload ssh: ```sudo service sshd reload```

### Redis
* First [create redis keys](#redis-keys) in the redis server container for each user
* To create a new password inside docker-dovecot-xapian run ```doveadm pw```, or a better scheme ```doveadm pw -s ARGON2ID```
* Copy the password hash and create key in redis container with it, any \'$\' in the password hash needs escaping with \ as well.

### Inside docker-dovecot-xapian
* Change password for doveback user: ```passwd doveback```
* Start dropbear ssh server in background: ```dropbear -R -E -p 127.0.0.1:22```
* Start reverse ssh tunnel to old dovecot machine: ```ssh -R 2222:localhost:22 -N SSHTUNUSER@OLDDOVCOTIP```

### Again on old dovecot machine
* Sync mail into docker-dovecot-xapian with the tunnel:
```sudo doveadm backup -u USERNAME@THISSERVER ssh doveback@127.0.0.1 -p 2222 -o "UserKnownHostsFile /dev/null" doas doveadm dsync-server -u REMOTEUSER@REMOTESERVER```
* ```doveadm backup``` is one way ```doveadm sync``` is two way
* USERNAME@THISSERVER and REMOTEUSER@REMOTESERVER would normally be the same unless THISSERVER does not use virtual mailboxes
* Repeat for each mailbox that is being migrated or use a script like:
```bash
#!/bin/sh
allusers="user1@ex.com user2@ex.com user3@ex.com user4@ex.com"
sshcmd="ssh doveback@127.0.0.1 -o \"UserKnownHostsFile /dev/null\" -p 2222"
echo "Syncing Mail..."
for usname in ${allusers}; do
  echo "Syncing $usname"
  sudo doveadm backup -u $usname $sshcmd doas doveadm dsync-server -u $usname
done
```
### Again inside docker-dovecot-xapian
* List processes: ```ps -A```
* kill ssh and dropbear processes:
```bash
kill -SIGTERM DROPBEARPID
kill -SIGTERM SSHPID
```

## Redis Keys
The following redis keys need setting for each user

| KEY                          | Description                                                                         | Example                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| userdb/user@example.com      | Username exists check, and json string of userdb fields                             | redis-cli set userdb/user@example.com {}<br>or unlimited storage<br> redis-cli set "userdb/user@example" {\\"quota_rule\\":\\"*:storage=0\\"}                                           |
| passdb/user@example.com      | Json user password hash string, hash can be copied from shadow                      | redis-cli set passdb/user@example.com {\\"password\\":\\"{CRYPT}$6$MOREPASSWORDHASH\\"}|
| VALI:user@example.com        | Postfix virtual mailbox alias key (If using postfix redis lookups), used to check existence and create aliases | redis-cli set "VALI:user@example.com" user@example.com |

## SSL Certificates
The path for certificates to be mounted in is: ```/etc/letsencrypt```, the actual certificates should then be in the directory ```live/$LETSENCRYPT```.  This is usually mounted from a letsencrpyt/dnsrobocert container.

## Security
Dovecot has its own rate limiting for failed logins, for extra security with firewalling use syslog-ng on the docker host and set the docker logging to journald so logs can be parsed by a service like fail2ban

## Overriding configuration
Mount the file ```override.conf``` into /etc/dovecot/, this is read last to override any settings.

## Github
Github Repository: [https://github.com/a16bitsysop/docker-dovecot-xapian](https://github.com/a16bitsysop/docker-dovecot-xapian)

## Environment Variables

| NAME        | Description                                                               | Default               |
| ----------- | ------------------------------------------------------------------------- | --------------------- |
| REDIS       | Name/container name or IP of the redis server                             | none                  |
| HOSTNAME    | Hostname for dovecot to use                                               | none                  |
| LETSENCRYPT | Folder name for ssl certs (/etc/letsencrypt/live/$LETSENCRYPT/cert.pem)   | none                  |
| POP3PORT    | Listen for pop3s on POP3PORT                                              | do not use this port  |
| RSPAMD      | Name/container name or IP of rspamd, for learn ham/spam                   | none                  |
| STUNNEL     | Use stunnel to encrypt redis traffic on port 6379 if set                  | unset                 |
| FETCH       | Copy email to 7 day expiring "Fetch" folder for another service to fetch  | unset                 |
| TIMEZONE    | Timezone to use inside the container, eg Europe/London                    | unset                 |

## Examples
To run connecting to container network exposing ports (accessible from host network), and docker managed volumes.  With ssl certificates mounted into /etc/letsencrypt
```bash
#docker container run -p 993:993 -p 995:995 --name dovecot --restart=unless-stopped --mount source=dovecot-var,target=/var/lib/dovecot --mount source=dovecot-mail,target=/var/vmail/mailboxes --mount source=ssl-certs,target=/etc/letsencrypt -d a16bitsysop/dovecot-xapian
```
