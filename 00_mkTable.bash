#!/usr/bin/env bash

set -e

# make sqlite3 table with all runs
#     | subj | date | Project | complete? | runs:missing | runs:done | runs:all | rawdir | bad channel dir |

source funcs.bash

function mktable {
 db=$1
 [ -z "$db" ] && echo "mktable: need a db to work with!" && return 1
 sqlite3 $db '
  create table badchannel(
    id       integer,
    date     integer,
    proj     text,
    complete integer,
    missruns text,
    doneruns text,
    allruns  text,
    rawdir   text,
    bcpat    text
  );'
}

# make table if we dont have it
db="badchannel.db"
[ -r "$db" ]  && rm $db
mktable $db

# go through raw data, create sql
echo -n > add.sql
for d in /data/Luna1/MultiModal/MEG_Raw/*/*/; do
 addDirToSql $d >> add.sql || echo "$d failed!" >&2
done

sqlite3 $db < add.sql

