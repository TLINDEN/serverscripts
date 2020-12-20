#!/bin/sh

# create symlinks to snapshots
# for home only
snap=/snap
zfs=/home/.zfs/snapshot
users="gedefa scip torres"

for user in $users; do
  mkdir -p $snap/home/$user
done

for snapshot in `cd $zfs; ls -1d *` ; do
  for user in $users; do
    ln -sf $zfs/$snapshot/$user $snap/home/$user/$snapshot
  done
done

