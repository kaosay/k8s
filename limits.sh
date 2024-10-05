#!/bin/bash

echo
echo "Change-->/etc/security/limits.conf"
echo "--------Before--------"
tail /etc/security/limits.conf

cat <<EOL >> /etc/security/limits.conf
root		soft	nofile		100001
root		hard	nofile		100002
*		soft	nofile		100001
*		hard	nofile		100002
root		soft	memlock		unlimited
root		hard	memlock		unlimited
*		soft	memlock		unlimited
*		hard	memlock		unlimited
EOL

echo "--------Now--------"
tail /etc/security/limits.conf

