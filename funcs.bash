

# exists returns success, failure otherwise
function checkexists {
 db=$1; shift
 id=$1; date=$2; proj=$3;
 res=$(sqlite3 $db "
   select * from badchannel where
    id=$id and date=$date and proj like '$proj';
 ")

 [ -n "$res" ] && return 0
 return 1
}
function checkDirExists {
 db=$1; shift
 rawdir=$1;
 [ -z "$db" -o ! -r "$db" ]         && echo "checkDir needs existing db (not '$db')!"         >&2 && return 1
 [ -z "$rawdir" -o ! -d "$rawdir" ] && echo "checkDir needs existing rawdir (not '$rawdir')!" >&2 && return 1

 res=$(sqlite3 $db "select * from badchannel where rawdir like '$rawdir';") 
 [ -z "$res" ] && return 1

 return 0
}

function colonDelmRuns {
   proj=$1; shift;
   d=$1; shift;
   fpat="$1";shift;

   case $proj in
    Rest)
     regex='(?<rname>empty|rest)'
    ;;
    *)
     regex='run(?<rname>\d+)'
   esac
   find -L $d -iname "$fpat" 2>/dev/null |perl -ne "\$r{$+{rname}}++ if m/$regex/i; END{print join(':',sort {\$a<=>\$b} keys %r)}"
}

# report what is in 2 that is not in 1
# colListDiff 2:3 1:2:3:4 => 1:4
function colListDiff {
 comm -13 <(tr ':' '\n' <<< $1) <(tr ':' '\n' <<< $2) | tr '\n' ':' | sed s/:$//
 echo
}

# find bad channel files
#  bad channel text files are in different directories given the task
function projBCDir {
 proj=$1;id=$2; date=$3;
 case $proj in
  WM)
    bcsearchdir=/data/Luna1/Natalie/badchannels/ 
    filepat="${id}_run*_bc_wm.txt"
  ;;
  Clock)
    bcsearchdir=/data/Luna1/MultiModal/Clock/$id*/MEG/
    filepat="*bad*.txt"
  ;;
  *)
    bcsearchdir=/data/Luna1/MultiModal/MEG_Raw/${id}_$date/*/
    filepat="*bad*.txt"
  ;;
 esac
 echo "$bcsearchdir $filepat"
}


function iddateFromDir {
 d="$1"
 [ -z "$d" -o ! -d $d ] && echo "iddateFromDir needs a valid dir ('$d' is not)" >&2 && return 1

 # get id and date
   id=$(sed 's:.*/\([0-9]\{5\}\)_.*:\1:' <<< $d | sed "s:$d::" )
 date=$(sed 's:.*_\([0-9]\{8\}\)/.*:\1:' <<< $d | sed "s:$d::")
 
 [ -z "$id" -o -z "$date" ]  && echo "bad dir name (no 'id_date'): $d " >&2 && return 1
 echo "$id $date"
}

#
# echo sql insert statements
#
function addDirToSql {
 iddate=($(iddateFromDir $1) ) 
 [ -z "$iddate" ] && return 1
 id=${iddate[0]}
 date=${iddate[1]}

 nproj=0;
 # determine project based on filenames
 # N.B. likely to have 2 projects per subject (WM/Cog/clock and Rest)
 for proj in Cog WM Clock Switch Rest; do


   ## What MEG runs do we have?
   # most projects have their name in the fif. 
   projfix="$proj"
   # but rest is everywhere
   [ "$proj" == "Rest" ] && projfix=""
   runs=$(colonDelmRuns $proj $d  "*$projfix*_raw.fif" )
   #runs=$(find -L $d -iname "|perl -ne "push \$r{$+{rname}}++ if m/$regex/i; END{print join(':',keys %r)}")

   # nothing on this project
   [ -z "$runs" ] && continue

   ## What bad channel annotations do we have
   bcdirAndPat=($(projBCDir  $proj $id $date))
   bcfiles=$(echo ${bcdirAndPat[@]} | sed 's: :/:')
   doneruns="$(colonDelmRuns $proj ${bcdirAndPat[@]} )"
   missruns="$(colListDiff "$doneruns" "$runs")"

   # did we annotate all of the aviable runs?
   completed=0;
   [ -z "$missruns" ] && completed=1 && missruns=''

   #checkexists badchannel.db $id $date $proj ||
   # sqlite3 badchannel.db "insert into badchannel 
   echo "insert into badchannel 
             (id, date, proj, complete, missruns, doneruns, allruns, rawdir,bcpat)
     values  ($id,$date,'$proj',$completed,'$missruns','$doneruns','$runs','$d','$bcfiles');"

   let "nproj = $nproj + 1"

 done

 [ $nproj -lt 1 ] && echo "nothing found in $d!" >&2 && return 1

 return 0
}

## update or insert an entry
# USAGE:
#   updateOrAddDir badchannel.db /data/Luna1/MultiModal/MEG_Raw/11353_20141230/141230/
function updateOrAddDir {
 db=$1; shift
 [ -z "$db" -o ! -r "$db" ] && echo "updateOrAddDir: need existing db $db" >&2 && return 1

 d="$1"
 [ -z "$d" ] && echo "updateOrAddDir: need '$d' to be a dir!" >&2 && return 1

 # if we haven't seen this dir we just need to add it
 if ! checkDirExists $db $d ; then
    sql=$(addDirToSql  $d)
    [ -z "$sql" ] && echo "updateOrAddDir: bad sql" >&2 &&  return 1
    sqlite3 $db "$sql"
    return 0
 fi

 ## update with new bad channel text files
 ## ...if there are any new files
 ## use the bad channel text file path from the database to query for text files
 sqlite3 -separator ',' $db "select 
             rowid,proj,allruns,doneruns,bcpat from badchannel where rawdir like '$d'" | 
  while IFS=, read rowid proj allruns prevdone bcpat; do
   doneruns=$(colonDelmRuns $proj "$bcpat" "*")

   [ -z "$prevdone" -a -z "$doneruns"           ] || 
   [ -n "$prevdone" -a "$doneruns" == $prevdone ] && continue #&& echo "  $id $date $proj uptodate" 

   missruns="$(colListDiff "$doneruns" "$allruns")"
   # did we annotate all of the aviable runs?
   completed=0;
   [ -z "$missruns" ] && completed=1 && missruns=''

   sqlite3 $db "update (doneruns,missruns,complete) values 
                       ('$doneruns','$missruns',$complete) where rowid == $rowid"
 done



 
}
