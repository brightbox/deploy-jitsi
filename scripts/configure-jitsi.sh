#!/bin/bash

FQDN=$1
CIP=$2
ACME_EMAIL=$3


echo "Checking DNS is setup right..."
FQDN_IPS=$(host $FQDN | grep -oE "address (.*)" | awk '{print $2}')

if [ -z "$FQDN_IPS" ] ; then
    echo "FQDN $FQDN doesn't resolve"
    exit 1
fi


for fqdn_ip in $FQDN_IPS ; do
    echo "Checking $fqdn_ip points at me..."
    if ! (host $CIP | grep -q $fqdn_ip) ; then
        echo "FQDN $FQDN has IP address $fqdn_ip which doesn't resolve to the cloud ip $CIP"
    fi
done

wget -qO - https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -
apt-add-repository 'deb https://download.jitsi.org stable/' >/dev/null
apt-get install -qy debconf-utils

debconf-set-selections <<EOF
jicofo	jitsi-videobridge/jvb-hostname	string	$FQDN
jitsi-meet-prosody	jitsi-videobridge/jvb-hostname	string	$FQDN
jitsi-meet-web-config	jitsi-videobridge/jvb-hostname	string	$FQDN
jitsi-videobridge	jitsi-videobridge/jvb-hostname	string	$FQDN
jitsi-meet-prosody	jitsi-meet-prosody/jvb-hostname	string	$FQDN
jitsi-meet-web-config	jitsi-meet/cert-choice	select	Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)
EOF

export DEBIAN_FRONTEND=noninteractive

if ! dpkg-query -W jitsi-meet ; then
    apt-get install -qy jitsi-meet
else
    dpkg-reconfigure jitsi-videobridge jitsi-meet jitsi-meet-prosody jicofo jitsi-meet-web-config
fi

echo $ACME_EMAIL | /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
