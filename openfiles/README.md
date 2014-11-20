Check for open files usage of RTPengine or Asterisk
===================================================

Usage (do this on the monitored host):
* check_openfiles.sh - call it by cron every minute
* openfiles.sh - extend your SNMPd 
** echo "pass .1.3.6.1.4.1.2021.255 /usr/local/sbin/openfiles.sh .1.3.6.1.4.1.2021.255" >> /etc/snmp/snmpd.conf
