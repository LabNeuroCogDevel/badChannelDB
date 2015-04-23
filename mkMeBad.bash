#!/usr/bin/env bash

##
# find raw fifs that need bad channels to be annotated
##
cd $(dirname $0)
source funcs.bash

db=badchannel.db
proj=$1
if [ -z "$proj" ]; then
  echo "Choices: " 
  sqlite3 $db 'select proj from badchannel group by proj' |tr '\n' ' ' 
  echo " [Ctrl+C to quit]"
  echo -n "> "
  read proj
  echo $proj
fi

findIncomplete $db $proj
