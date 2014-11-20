#!/bin/bash

ASTFILES=/tmp/astfiles
ASTPORTS=/tmp/astports
RTPFILES=/tmp/rtpfiles
RTPFILES2=/tmp/rtpfiles2

ASTPID=`pidof asterisk`
if [ -z "$ASTPID" ] ; then
	echo "0" > $ASTFILES
else 
	echo `ls -1 /proc/${ASTPID}/fd | wc -l` > $ASTFILES
	lsof -p `pidof asterisk`| egrep 'UDP [^:]+:[12][0-9][0-9][0-9][0-9]' | wc -l > $ASTPORTS
fi

RTPPID=`/bin/pidof rtpengine | cut -d" " -f1`
if [ -z "$RTPPID" ] ; then
	echo "0" > $RTPFILES
else 
	echo `ls -1 /proc/${RTPPID}/fd | wc -l` > $RTPFILES
fi

RTPPID2=`/bin/pidof rtpengine | cut -d" " -f2`
if [ -z "$RTPPID2" ] ; then
	echo "0" > $RTPFILES2
else
	echo `ls -1 /proc/${RTPPID2}/fd | wc -l` > $RTPFILES2
fi

