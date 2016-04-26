#!/bin/bash
#set -x
#####
function redis_query {
   RedisHost=$1
   RedisKey=$2
   RedisValue=$3
   TTL=$4

   if [ $TTL -le 1 ]
   then
      echo "ERROR TTL"
      return 1
   else
      let "TTL -= 1"
      RedisQuery=$(redis-cli -h $RedisHost GET $RedisKey 2>&1)
      if [[ "$RedisQuery" == *MOVED* ]]
      then
          MovedHost=$(echo $RedisQuery | sed 's/MOVED\ [0-9]*\ //; s/:.*//')
          redis_query $MovedHost $RedisKey $RedisValue $TTL
          return $?
      fi

      if [[ "$RedisQuery" == *CLUSTERDOWN* ]]
      then
          echo -n "-"
          return 1
      fi

      if [[ "$RedisQuery" == *Connection* ]]
      then
          echo -n "?"
          return 1
      else
          if [[ $RedisQuery == $RedisValue ]];
          then
               echo -n "+"
               let "RedisValue += 1"
               let "NewRedisValue  = RedisValue"
               redis-cli -h $RedisHost SET $RedisKey $NewRedisValue > /dev/null
		return 0
          else
               echo
               echo "Bad response: $RedisQuery  :+: $RedisHost : $RedisKey : $RedisValue"
               if [[ $RedisQuery == "" ]];
               then
                    echo -n
                    redis-cli -h $RedisHost SET $RedisKey $RedisValue
               fi
      redis-cli -h $RedisHost SET $RedisKey 0
	       return 1
          fi
      fi
   fi
}

#for ii in $(echo {A..Z} {a..z} {0..9}); do let "$ii = 0"; done
for ii in $(echo key{1..100000}); do let "$ii = 0"; done

SERVERS="10.60.4.27:6379
10.60.4.6:6379
10.60.3.16:6379
10.60.4.5:6379
10.60.3.17:6379
10.60.4.7:6379
10.60.1.3:6379
10.60.1.9:6379
10.60.3.15:6379
"

SERVER=($SERVERS)
NUM=${#SERVER[*]}

while [ 1 ]
do
  II=${SERVER[$((RANDOM%NUM))]}
  RedisHost=$(echo $II | sed 's/:.*//')
  RedisPort=$(echo $II | sed 's/.*://')
  echo "$II $RedisHost $RedisPort"

  echo -n "+"
  for ii in $(echo key{1..100000})
  do
     let "tmpii = $ii"
     redis_query $RedisHost $ii $tmpii $NUM
     if [ $? -eq 0 ]
     then
         let "$ii += 1"
     fi
  done

  echo "+="
  sleep 1
done
