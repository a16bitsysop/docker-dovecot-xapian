FROM alpine:3.14
LABEL maintainer="Duncan Bellamy <dunk@denkimushi.com>"

RUN mkdir /var/vmail && addgroup -S -g 5000 vmail \
&& adduser -S -u 5000 -h /var/vmail/mailboxes --gecos "virtual mailbox user" --ingroup vmail vmail

COPY --chown=vmail:vmail sieve /var/vmail/sieve

SHELL [ "/bin/ash", "-o", "pipefail", "-c" ]
# hadolint ignore=DL3018
RUN apk add -u --no-cache dovecot-lmtpd dovecot-pop3d dovecot-pigeonhole-plugin dovecot-fts-xapian \
 curl dropbear dropbear-ssh doas stunnel \
 unzip mupdf-tools \
&&  mv /usr/bin/curl /var/vmail/sieve/bin/ \
&& rm -rf /etc/dovecot/conf.d/* \
&& mkdir /etc/dropbear \
&& adduser -D -h /home/doveback doveback \
&& echo "doveback:$(openssl rand -base64 32)" | chpasswd \
&& echo "permit nopass doveback as root cmd doveadm" >> /etc/doas.conf

WORKDIR /usr/libexec/dovecot
COPY decode2text.sh ./

WORKDIR /etc/dovecot
COPY conf ./

WORKDIR /usr/local/bin
COPY travis-helpers/set-timezone.sh entrypoint.sh post-run.sh ./
ENTRYPOINT [ "entrypoint.sh" ]

COPY stunnel.conf /etc/stunnel/stunnel.conf

EXPOSE 993 995 2221
VOLUME [ "/var/lib/dovecot" "/var/vmail/mailboxes" ]
