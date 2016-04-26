#!/bin/bash
#set -x

#CONFIG SECTION
SLEEP=1
KEYS=100
KEYPREFIX=key
SERVERS="10.60.4.207:6379
10.60.4.106:6379
10.60.4.216:6379
10.60.4.105:6379
10.60.4.217:6379
10.60.4.107:6379
10.60.4.210:6379
10.60.4.209:6379
10.60.4.215:6379
"
#END CONFIG SECTION

#FUNCTIONS
function runParallel () {
 cmd=$1
 args=$2
 number=$3
 currNumber="1024"

function redis_query {
   RedisHost=$1
   RedisPort=$2
   RedisKey=$3
   RedisValue=$4
   TTL=$5

   if [ $TTL -le 1 ]
   then
      echo "ERROR TTL"
      return 1
   else
      let "TTL -= 1"
      RedisQuery=$(redis-cli -h $RedisHost -p $RedisPort GET $RedisKey 2>&1)
      if [[ "$RedisQuery" == *MOVED* ]]
      then
          MovedHost=$(echo $RedisQuery | sed 's/MOVED\ [0-9]*\ //; s/:.*//')
          MovedPort=$(echo $RedisQuery | sed 's/MOVED\ [0-9]*\ //; s/.*://')
          redis_query $MovedHost $MovedPort $RedisKey $RedisValue $TTL
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
               let "NewRedisValue = RedisValue"
               redis-cli -h $RedisHost -p $RedisPort SET $RedisKey $NewRedisValue > /dev/null
                return 0
          else
               echo
               echo "Bad response: $RedisQuery :+: $RedisHost : $RedisKey : $RedisValue"
      echo "redis-cli -h $RedisHost -p $RedisPort GET $RedisKey   ::: $RedisQuery"
               if [[ $RedisQuery == "" ]];
               then
                    echo -n
                    redis-cli -h $RedisHost -p $RedisPort SET $RedisKey $RedisValue
               fi
      redis-cli -h $RedisHost SET $RedisKey 0
               return 1
          fi
      fi
   fi
}

#create redis values.
#if argc == 0 when exit
#if argc == 1, then $1 is keyname. get first server from server list
function add_redis_value0 {

        if [ $# -eq 0 ]
        then
            return 1
        fi

        if [ $# -eq 1 ]
        then
            #get first server
            SERVER=($SERVERS)
            NUM=${#SERVER[*]}
            RedisHost=$(echo ${SERVER[0]} | sed 's/:.*//')
            RedisPort=$(echo ${SERVER[0]} | sed 's/.*://')

            add_redis_value0 $1 $RedisHost $RedisPort $NUM

            return $?
        fi

        RedisKey=$1
        RedisHost=$2
        RedisPort=$3
        TTL=$4

        if [ $TTL -le 1 ]
        then
            echo "ERROR TTL"
            return 1
        else
            let "TTL -= 1"
            RedisQuery=$(redis-cli -h $RedisHost -p $RedisPort SET $RedisKey 0 2>&1)
            if [[ "$RedisQuery" == *MOVED* ]]
            then
                MovedHost=$(echo $RedisQuery | sed 's/MOVED\ [0-9]*\ //; s/:.*//')
                MovedPort=$(echo $RedisQuery | sed 's/MOVED\ [0-9]*\ //; s/.*://')
                add_redis_value0 $RedisKey $MovedHost $MovedPort $TTL
                return $?
            fi

            if [[ "$RedisQuery" == *CLUSTERDOWN* ]]
            then
                return 1
            fi
        fi
#        echo "-------------- $RedisKey : $RedisQuery ------------"
        return 0
}

#testing redis nodes.
function redis_ping {
        SERVER=($SERVERS)
        NUM=${#SERVER[*]}
        let "NUM -= 1" #ибо массив с нуля считается

	for i in $(echo "echo {0..$NUM}" | bash)  # не делайте так!
        do
            RedisHost=$(echo ${SERVER[$i]} | sed 's/:.*//')
            RedisPort=$(echo ${SERVER[$i]} | sed 's/.*://')
            Resp=$(redis-cli -h ${RedisHost} -p ${RedisPort} PING)
            if [[ "$Resp" != "PONG" ]]
            then
               echo "Server $RedisHost $RedisPort not response"
               return 1
            fi
        done
        return 0
}

#if $1 == "+XXX" where XXX is integer 
#     then add new XXX values into redis and local cache
#if $1 == "XXX" where XXX is integer and without leader "+" 
#     then create values from 1 to XXX
#if $1 and $2 is integer
#     then create values from $1 to $2

function init_redis_key {
        KEYS=${KEYS:-0}
        #echo "DEBUG: 1-> $1; 2-> $2; KEYS-> $KEYS ;"
        if [ ${1:0:1} == "+" ]
        then 
             NEWKEYS=${1:1}
             let "NEWKEYS += KEYS"
             let "KEYS += 1"
             init_redis_key ${KEYS} ${NEWKEYS}
             return $?
        fi

        if [ ! $2 ] 
        then
             init_redis_key 1 ${1}
             return $?
        fi

        if [ "$2" -gt "$1" ]
        then
	      for ii in $(echo "echo ${KEYPREFIX}{$1..$2}" | bash)  # не делайте так!
              do 
                   let "$ii = 0"; 
                   add_redis_value0 $ii
                   #TODO: Вот тут надо обработать ситуацию, когда редис обломился и не смог ничего записать. Иначе словим расхождение в ключах
              done
              return 0
        fi

        return 1
}


#MAIN PROGRAMM
redis_ping
if [ ! $? ]
then
   echo "Bad cluster configuration."
   echo "Please check and try again"
   return 1
fi 

init_redis_key ${KEYS}
###init_redis_key "+10"

MSERVER=($SERVERS)
MNUM=${#MSERVER[*]}

#Main section

while [ 1 ]
do
  MI=${MSERVER[$((RANDOM%NUM))]}
  MRedisHost=$(echo $MI | sed 's/:.*//')
  MRedisPort=$(echo $MI | sed 's/.*://')
  echo "$MI $MRedisHost $MRedisPort"

  echo -n "+"
  for mi in $(echo "echo ${KEYPREFIX}{1..$KEYS}" | bash)
  do
     let "tmpii = $mi"
     redis_query $MRedisHost $MRedisPort $mi $tmpii $NUM
     if [ $? -eq 0 ]
     then
         let "$mi += 1"
     fi
  done

  echo "+="

  init_redis_key "+10"
  let "KEYS += 9" #где-то я обсчитался в глобальном параметре. должна быть десятка, но в функции выше добавляется еденица. ай как некрасиво...
  sleep ${SLEEP}
done 

$cmd $args &
}

loop=0
# We will run 12 sleep commands for 10 seconds each 
# and only five of them will work simultaneously
while [ $loop -ne 12 ] ; do
    runParallel "sleep" 10 5
        loop=`expr $loop + 1`
done