#!/bin/bash
#change user
user="user"

for ii in $(echo {A..Z} {a..z}); do let "$ii = 0"; done

SERVERS="10.60.4.207:6379
10.60.4.106:6379
10.60.3.216:6379
10.60.4.105:6379
10.60.3.217:6379
10.60.4.107:6379
10.60.1.210:6379
10.60.1.209:6379
10.60.3.215:6379
"

SERVER=($SERVERS)
NUM=${#SERVER[*]}

while [ 1 ]
do
  I=${SERVER[$((RANDOM%NUM))]}
  RedisHost=$(echo $I | sed 's/:.*//')
  RedisPort=$(echo $I | sed 's/.*://')
  echo "$I $RedisHost $RedisPort"
  ssh $user@$RedisHost "sudo pkill -9 redis"
  echo "redis killed"
  sleep 40
  ssh $user@$RedisHost "sudo /etc/init.d/redis start"
  echo "redis started"
  sleep 4
done
