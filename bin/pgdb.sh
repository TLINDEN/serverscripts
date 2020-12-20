#!/bin/sh
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
user="backup"
when="$1"
which="$2"
base="/home/backup/database"
time=""
logfile="/var/log/database-backup.log"
pgid=`jls | grep db | awk '{print $1}'`

umask 077

logdone () {
   echo "`date` done: $1" >> $logfile
}

die () {
   echo "$1" > /dev/stderr
}

extscript () {
	# gpg -d /home/backup/database/phorum/hourly/09.sql.gz.asc | gunzip -c > 9.sql
	path=$1
	file=$2
	sql=`echo "$file" | sed 's/.gz//'`
	script="$path/${sql}-decrypt.sh"
	(
		echo "#!/bin/sh"
		echo "asc=$path/$file.asc"
		echo "sql=$sql"
		echo "echo Decrypting and Unpacking \$asc to current directory as \$sql:"
		echo "gpg -d \$asc | gunzip -c > \$sql"
		echo "echo done"
	) > $script
	chmod 700 $script
}

if test -n "$which"; then
    db=$which
else
    db=`jexec $pgid /root/bin/pgdb.sh list`
fi

case $when in
    "hourly")  time=`date +%H`;;
    "daily")   time=`date +%d`;;
    "monthly") time=`date +%b`;;
    *) echo "usage $0 { hourly | daily | monthly } [database]"; exit;;
esac



for database in $db; do
    dir="$base/$database/$when"
    file="$time.sql.gz"
    msg="$database $when $time"
    (
        mkdir -p $dir
        jexec $pgid /root/bin/pgdb.sh dump $database > "$dir/$file"
        rm -f "$dir/$file.asc"
        gpg --encrypt --armor -r "root user" "$dir/$file"
        rm -f "$dir/$file"
	    extscript $dir $file
    ) && logdone $msg || die $msg 
done
