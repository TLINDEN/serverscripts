#!/bin/sh
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
src="/backup/database"
updir="/backup/upload"
sftpdir="/e3"
logfile="/var/log/backup-upload-log.log"
state="/var/log/.backupdone"
tmp=/tmp/$$.log
zfsdirs="/ /usr/home /var/log /var/audit /jail"
snapshot="hourly.0"
gelidirs=""


log () {
   echo "`date` $*" >> $logfile
}

md() {
	dir=$1
        echo "mkdir $dir" | sftp backup > /dev/null 2>&1
}

zfile() {
  dir=$1
  echo "$dir" | sed 's#/##g'
}

backdb() {
  log "Starting DB Dump uploads"
  md db
  files=`find $src -newer $state -type f ! -name "*.sql"`
  for file in $files; do
    dst=`dirname $file | sed -e "s#$src/##" -e 's#/#_#g'`
    md db/$dst
    log "uploading $file to backup:db/$dst/"
    scp $file backup:db/$dst/
  done
  log "done"
}

backzfs() {
  log "Starting ZFS Backups"
  md $sftpdir/zfs

  fdir=$1
  if test -n "$fdir"; then
    zfsdirs=$fdir
  fi

  for dir in $zfsdirs; do
	cd ${dir}/.zfs/snapshot
	if test -d $snapshot; then
		name=""
		if test "$dir" = "/"; then
			name=root
                else
                        name=`zfile $dir`
		fi
		tar cpzf $updir/$name.tgz.0 $snapshot
		md $sftpdir/zfs/$name
		old=`echo "ls $sftpdir/zfs/$name" | sftp backup | egrep -v "(Connected|sftp)" | sed -e "s#$sftpdir/zfs/$name/##g" | rev`
		for N in $old; do
		next=`expr $N + 1`
			if test $next -gt 3; then
				echo "rm $sftpdir/zfs/$name/$N" | sftp backup
			else
				echo "rename $sftpdir/zfs/$name/$N $sftpdir/zfs/$name/$next" | sftp backup
			fi
		done
		log "uploading $updir/$name.tgz.0 to backup:$sftpdir/zfs/$name/0"
		scp $updir/$name.tgz.0 backup:$sftpdir/zfs/$name/0 && rm -f $updir/$name.tgz.0
	fi
  done
  log done
}

backgeli() {
  log "Starting GELI Backups"
  md geli
  for dir in $gelidirs; do
	name=`echo $dir | sed 's/\//_/g'`
	tar cpzf $updir/$name.tgz $dir
        gpg --encrypt --armor -r "root user" $updir/$name.tgz
	rm -f $updir/$name.tgz
	mv $updir/$name.tgz.asc $updir/$name.tgz.asc.0
	md geli/$name
	old=`echo "ls zfs/$name" | sftp backup | egrep -v "(Connected|sftp)" | sed -e "s#zfs/$name/##g" | rev`
	for N in $old; do
		next=`expr $N + 1`
		if test $next -gt 3; then
			echo "rm geli/$name/$N" | sftp backup
		else
			echo "rename geli/$name/$N zfs/$name/$next" | sftp backup
		fi
	done
	log "uploading $updir/$name.tgz.asc.0 to backup:geli/$name/0"
	scp $updir/$name.tgz.asc.0 backup:geli/$name/0 && rm -f $updir/$name.tgz.asc.0
  done
  log done
}

case $1 in
	backdb)
		backdb
		;;
	backzfs)
		backzfs $2
		;;
	backgeli)
		backgeli
		;;
	*)
		backdb
		backzfs
		backgeli
		touch $state
		;;
esac
