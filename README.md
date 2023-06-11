# Efficiently copying files with Python 3.8+

In a nutshell:
* [shutil.copyfile()][] is probably good enough.
* Use [os.copy_file_range()][] for extra performance (with extra pitfalls)

## Using `shutil.copyfile()`

Since Python 3.8 the function [shutil.copyfile()][] is able to use more
efficient ways of copying files on some platforms. In Linux it uses the
[sendfile(2)][] syscall, which avoids the kernel- to userspace memory copies.

The environment for this experiment was set up as follows:

```
worker@copy-file-test:/$ uname -a
Linux copy-file-test 5.17.12-300.fc36.x86_64 #1 SMP PREEMPT Mon May 30 16:56:53 UTC 2022 x86_64 GNU/Linux

worker@copy-file-test:/$ apt list --installed 2>&1 | grep ^libc6\/
libc6/stable,now 2.31-13+deb11u6 amd64 [installed,automatic]

worker@copy-file-test:/$ carlos@rilke:~/src/copy-file-range-test$ python3 --version
Python 3.11.3
```

The Python script [copy-file](./copy-file) was running inside a Kubernetes
pod. Several NFS file systems were mounted on it.

In this example we copy a file from one NFS mount to another NFS mount on
a different NFS server

```
worker@copy-file-test:/$ mount | grep /data/bol-data-layer-data-green-001
bodh1lnxnas-02.ecmwf.int:/mnt/bodh1lnxnas-02_pool/eccharts/datastore_dh1_00 on /data/bol-data-layer-data-green-001 type nfs (rw,relatime,vers=3,rsize=131072,wsize=131072,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=10.120.5.10,mountvers=3,mountport=734,mountproto=udp,local_lock=none,addr=10.120.5.10)

worker@copy-file-test:/$ copy-file --verbose /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001 /data/bol-data-layer-data-green-001/pepe                                                                                                                                                            
Created tmp file /data/bol-data-layer-data-green-001/pepegrwq38lp
copy_file_stdlib: Wrote 7930080066 byte(s)
Renaming /data/bol-data-layer-data-green-001/pepegrwq38lp to /data/bol-data-layer-data-green-001/pepe
```

Here `strace` shows the file being copied using the [sendfile(2)][] syscall,
thus avoiding kernel- to userspace memory copies:

```
worker@copy-file-test:/$ strace -f copy-file --verbose /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001 /data/bol-data-layer-data-green-001/pepe
[..]
openat(AT_FDCWD, "/data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/data/bol-data-layer-data-green-001/pepee9ygkte8", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666) = 4
sendfile(4, 3, [0] => [1784938496], 7930080066) = 1784938496
sendfile(4, 3, [1784938496] => [3103522816], 7930080066) = 1318584320
sendfile(4, 3, [3103522816] => [5251002368], 7930080066) = 2147479552
sendfile(4, 3, [5251002368] => [7398481920], 7930080066) = 2147479552
sendfile(4, 3, [7398481920] => [7930080066], 7930080066) = 531598146
sendfile(4, 3, [7930080066], 7930080066) = 0
close(4)                                = 0
close(3)                                = 0
[..]
```


## Using `os.copy_file_range()`

Since Python 3.8, the function [os.copy_file_range()][] delegates the copying to the syscall
[copy_file_range(2)][]. That syscall requires:
* Linux kernel 5.3 or newer
* glibc 2.27 or newer

Additionally (see https://lwn.net/Articles/846403/) things don't always work
unless both source and target files are:
* regular files, and
* in the same storage device.

First we copy a file to a destination in the same device:

```
worker@copy-file-test:/$ mount | grep /data/bol-data-layer-data-green-000
bodh2lnxnas-02.ecmwf.int:/mnt/bodh2lnxnas-02_pool/eccharts/datastore_dh2_00 on /data/bol-data-layer-data-green-000 type nfs (rw,relatime,vers=3,rsize=131072,wsize=131072,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=10.120.6.10,mountvers=3,mountport=713,mountproto=udp,local_lock=none,addr=10.120.6.10)

worker@copy-file-test:/$ ls -l /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001
-rw-r--r-- 1 worker worker 7930080066 Jun 10 06:12 /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001

worker@copy-file-test:/$ copy-file --verbose /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001 /data/bol-data-layer-data-green-000/pepe                                                                                                                                                            
Created tmp file /data/bol-data-layer-data-green-000/pepewq6ka77s
copy_file_range(): Wrote 2147479552 byte(s)
copy_file_range(): Wrote 2147479552 byte(s)
copy_file_range(): Wrote 2147479552 byte(s)
copy_file_range(): Wrote 1487641410 byte(s)
Renaming /data/bol-data-layer-data-green-000/pepewq6ka77s to /data/bol-data-layer-data-green-000/pepe

worker@copy-file-test:/$ ls -l /data/bol-data-layer-data-green-000/pepe
-rw-r--r-- 1 worker worker 7930080066 Jun 10 10:09 /data/bol-data-layer-data-green-000/pepe
```

Running the program under `strace` showed the [copy_file_range(2)][] syscall in action:

```
worker@copy-file-test:/$ strace -f copy-file --verbose /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001 /data/bol-data-layer-data-green-000/pepe
[..]
openat(AT_FDCWD, "/data/bol-data-layer-data-green-000/pepezmb1yc1y", O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0600) = 3
openat(AT_FDCWD, "/data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001", O_RDONLY|O_CLOEXEC) = 4
copy_file_range(4, NULL, 3, NULL, 7930080066, 0) = 2147479552
copy_file_range(4, NULL, 3, NULL, 5782600514, 0) = 2147479552
copy_file_range(4, NULL, 3, NULL, 3635120962, 0) = 2147479552
copy_file_range(4, NULL, 3, NULL, 1487641410, 0) = 416612352
copy_file_range(4, NULL, 3, NULL, 1071029058, 0) = 1071029058
close(4)                                = 0
close(3)                                = 0
[..]
```


### The case for `copy_file_range(2)`

The advantage of [copy_file_range(2)][] over [sendfile(2)][]
is that, with the appropriate Linux kernel and glibc
versions, it _may_ be able to [avoid network transfers for NFS copies](https://datatracker.ietf.org/doc/html/rfc7862#page-6),
and gives a chance to filesystems to implement copy optimisations like
[reflinks](https://unix.stackexchange.com/questions/631237/in-linux-which-filesystems-support-reflinks)

in this example we have an NFS server running Debian 12, and mounting
several file systems of various types (with [pNFS][] enabled):

```
root@nfs-server:~# uname -a
Linux nfs-server 6.1.0-9-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.27-1 (2023-05-08) x86_64 GNU/Linux

root@nfs-server:~# apt list --installed 2>&1 | grep ^libc6\/ 
libc6/testing,now 2.36-9 amd64 [installed]

root@nfs-server:~# mount | grep nfs- | column -t
/dev/mapper/nfs-btrfs1  on  /data/nfs/btrfs1  type  btrfs  (rw,noatime,space_cache=v2,subvolid=5,subvol=/)
/dev/mapper/nfs-btrfs2  on  /data/nfs/btrfs2  type  btrfs  (rw,noatime,space_cache=v2,subvolid=5,subvol=/)
/dev/mapper/nfs-ext4    on  /data/nfs/ext4    type  ext4   (rw,noatime)
/dev/mapper/nfs-xfs2    on  /data/nfs/xfs2    type  xfs    (rw,noatime,attr2,inode64,logbufs=8,logbsize=32k,noquota)
/dev/mapper/nfs-xfs1    on  /data/nfs/xfs1    type  xfs    (rw,noatime,attr2,inode64,logbufs=8,logbsize=32k,noquota)

root@nfs-server:~# cat /etc/exports 
/data/nfs/btrfs1        10.0.0.0/24(rw,sync,mp,pnfs,no_subtree_check)
/data/nfs/btrfs2        10.0.0.0/24(rw,sync,mp,pnfs,no_subtree_check)
/data/nfs/ext4  10.0.0.0/24(rw,sync,mp,pnfs,no_subtree_check)
/data/nfs/xfs1  10.0.0.0/24(rw,sync,mp,pnfs,no_subtree_check)
/data/nfs/xfs2  10.0.0.0/24(rw,sync,mp,pnfs,no_subtree_check)
```

We also have an NFS client VM running Debian 12, and mounting all those
NFS shares with NFS version 4.2:

```
root@nfs-client:~# uname -a
Linux nfs-client 6.1.0-9-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.27-1 (2023-05-08) x86_64 GNU/Linux

root@nfs-client:~# apt list --installed 2>&1 | grep ^libc6\/ 
libc6/testing,now 2.36-9 amd64 [installed]

root@nfs-client:~# mount | grep nfs | column -t
10.0.0.1:/data/nfs/ext4    on  /data/nfs/ext4    type  nfs4  (rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.0.0.2,local_lock=none,addr=10.0.0.1)
10.0.0.1:/data/nfs/xfs2    on  /data/nfs/xfs2    type  nfs4  (rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.0.0.2,local_lock=none,addr=10.0.0.1)
10.0.0.1:/data/nfs/btrfs2  on  /data/nfs/btrfs2  type  nfs4  (rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.0.0.2,local_lock=none,addr=10.0.0.1)
10.0.0.1:/data/nfs/btrfs1  on  /data/nfs/btrfs1  type  nfs4  (rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.0.0.2,local_lock=none,addr=10.0.0.1)
10.0.0.1:/data/nfs/xfs1    on  /data/nfs/xfs1    type  nfs4  (rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.0.0.2,local_lock=none,addr=10.0.0.1)

-bash: python: command not found
root@nfs-client:~# python3 --version
Python 3.11.2
```

If we copy a 1 GiB file over NFS, we see that [os.copy_file_range()][] gets used:

```
carlos@nfs-client:~$ ./copy-file --verbose /data/nfs/xfs1/zeroes /data/nfs/xfs1/pepe
Created tmp file /data/nfs/xfs1/pepeksfs4l99
copy_file_range(): Wrote 1073741824 byte(s)
Renaming /data/nfs/xfs1/pepeksfs4l99 to /data/nfs/xfs1/pepe
carlos@nfs-client:~$ 
```

On the server side we see an interesting warning:

```
root@nfs-server:~# journalctl -f
[..]
Jun 11 10:19:08 nfs-server kernel: XFS (dm-1): Using experimental pNFS feature, use at your own risk!
[..]
```

And finally we see basically no network traffic for transferring the
_contents_ of the file during the whole operation:

```
12:46:29.305314 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 9744:9952, ack 8181, win 16092, options [nop,nop,TS val 3392919623 ecr 3877545950], length 208: NFS request xid 490414542 204 getattr fh 0,2/53
12:46:29.305769 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 8181:8425, ack 9952, win 24559, options [nop,nop,TS val 3877558366 ecr 3392919623], length 244: NFS reply xid 490414542 reply ok 240 getattr NON 3 ids 0/60786020 sz 1862311117
12:46:29.306033 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [.], ack 8425, win 16092, options [nop,nop,TS val 3392919624 ecr 3877558366], length 0
12:46:29.306592 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 9952:10288, ack 8425, win 16092, options [nop,nop,TS val 3392919625 ecr 3877558366], length 336: NFS request xid 507191758 332 getattr fh 0,2/53
12:46:29.347814 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 8425:8833, ack 10288, win 24559, options [nop,nop,TS val 3877558408 ecr 3392919625], length 408: NFS reply xid 507191758 reply ok 404 getattr NON 6 ids 0/60786020 sz 1862311117
12:46:29.348249 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 10288:10528, ack 8833, win 16092, options [nop,nop,TS val 3392919666 ecr 3877558408], length 240: NFS request xid 523968974 236 getattr fh 0,2/53
12:46:29.348430 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 8833:8997, ack 10528, win 24559, options [nop,nop,TS val 3877558409 ecr 3392919666], length 164: NFS reply xid 523968974 reply ok 160 getattr NON 4 ids 0/60786020 sz 1862311117
12:46:29.348685 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 10528:10792, ack 8997, win 16092, options [nop,nop,TS val 3392919667 ecr 3877558409], length 264: NFS request xid 540746190 260 getattr fh 0,2/53
12:46:29.350240 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 8997:9229, ack 10792, win 24559, options [nop,nop,TS val 3877558411 ecr 3392919667], length 232: NFS reply xid 540746190 reply ok 228 getattr NON 4 ids 0/60786020 sz 1862311117
12:46:29.351014 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 10792:11012, ack 9229, win 16092, options [nop,nop,TS val 3392919669 ecr 3877558411], length 220: NFS request xid 557523406 216 getattr fh 0,2/53
12:46:29.351251 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 9229:9473, ack 11012, win 24559, options [nop,nop,TS val 3877558412 ecr 3392919669], length 244: NFS reply xid 557523406 reply ok 240 getattr NON 3 ids 0/60786020 sz 1862311117
12:46:29.351495 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 11012:11300, ack 9473, win 16092, options [nop,nop,TS val 3392919670 ecr 3877558412], length 288: NFS request xid 574300622 284 getattr fh 0,2/53
12:46:29.351639 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 9473:9829, ack 11300, win 24559, options [nop,nop,TS val 3877558412 ecr 3392919670], length 356: NFS reply xid 574300622 reply ok 352 getattr NON 5 ids 0/60786020 sz 1862311117
12:46:29.351927 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 11300:11620, ack 9829, win 16092, options [nop,nop,TS val 3392919670 ecr 3877558412], length 320: NFS request xid 591077838 316 getattr fh 0,2/53
12:46:29.352161 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 9829:9993, ack 11620, win 24559, options [nop,nop,TS val 3877558413 ecr 3392919670], length 164: NFS reply xid 591077838 reply ok 160 getattr NON 5 ids 0/60786020 sz 1862311117
12:46:29.357037 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 9993:10209, ack 11620, win 24559, options [nop,nop,TS val 3877558418 ecr 3392919670], length 216
12:46:29.357349 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [.], ack 10209, win 16092, options [nop,nop,TS val 3392919675 ecr 3877558413], length 0
12:46:29.357373 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 11620:11708, ack 10209, win 16092, options [nop,nop,TS val 3392919676 ecr 3877558413], length 88
12:46:29.357787 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 11708:11936, ack 10209, win 16092, options [nop,nop,TS val 3392919676 ecr 3877558413], length 228: NFS request xid 607855054 224 getattr fh 0,2/53
12:46:29.357902 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [.], ack 11936, win 24559, options [nop,nop,TS val 3877558419 ecr 3392919676], length 0
12:46:29.357923 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 10209:10325, ack 11936, win 24559, options [nop,nop,TS val 3877558419 ecr 3392919676], length 116: NFS reply xid 607855054 reply ok 112 getattr NON 3 ids 0/60786020 sz 1862311117
12:46:29.358233 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 11936:12156, ack 10325, win 16092, options [nop,nop,TS val 3392919676 ecr 3877558419], length 220: NFS request xid 624632270 216 getattr fh 0,2/53
12:46:29.358340 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 10325:10525, ack 12156, win 24559, options [nop,nop,TS val 3877558419 ecr 3392919676], length 200: NFS reply xid 624632270 reply ok 196 getattr NON 3 ids 0/60786020 sz 1862311117
12:46:29.358496 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 12156:12416, ack 10525, win 16092, options [nop,nop,TS val 3392919677 ecr 3877558419], length 260: NFS request xid 641409486 256 getattr fh 0,2/53
12:46:29.360068 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 10525:10793, ack 12416, win 24559, options [nop,nop,TS val 3877558421 ecr 3392919677], length 268: NFS reply xid 641409486 reply ok 264 getattr NON 4 ids 0/60786020 sz 1862311117
12:46:29.360709 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 12416:12668, ack 10793, win 16092, options [nop,nop,TS val 3392919679 ecr 3877558421], length 252: NFS request xid 658186702 248 getattr fh 0,2/53
12:46:29.361943 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 10793:10949, ack 12668, win 24559, options [nop,nop,TS val 3877558423 ecr 3392919679], length 156: NFS reply xid 658186702 reply ok 152 getattr NON 5 ids 0/60786020 sz 1862311117
12:46:29.362270 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [P.], seq 12668:12912, ack 10949, win 16092, options [nop,nop,TS val 3392919680 ecr 3877558423], length 244: NFS request xid 674963918 240 getattr fh 0,2/53
12:46:29.362389 IP 10.0.0.1.2049 > 10.0.0.2.794: Flags [P.], seq 10949:11129, ack 12912, win 24559, options [nop,nop,TS val 3877558423 ecr 3392919680], length 180: NFS reply xid 674963918 reply ok 176 getattr NON 4 ids 0/60786020 sz 1862311117
12:46:29.404864 IP 10.0.0.2.794 > 10.0.0.1.2049: Flags [.], ack 11129, win 16092, options [nop,nop,TS val 3392919723 ecr 3877558423], length 0
```


[copy_file_range(2)]: https://man7.org/linux/man-pages/man2/copy_file_range.2.html
[os.copy_file_range()]: https://docs.python.org/3/library/os.html#os.copy_file_range
[os.sendfile()]: https://docs.python.org/3/library/os.html#os.sendfile
[pNFS]: http://www.pnfs.com/
[sendfile(2)]: https://man7.org/linux/man-pages/man2/sendfile.2.html
[shutil.copyfile()]: https://docs.python.org/3/library/shutil.html#shutil.copyfile
