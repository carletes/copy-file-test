# Efficiently copying files with Python 3

In a nutshell:
* Use [os.copy_file_range()][] when possible.
* Use [shutil.copyfile()][] on other cases.

## Using `os.copy_file_range()`

Since Python 3.8, the function [os.copy_file_range()][] delegates the copying to the syscall
[copy_file_range(2)][]. That syscall requires:
* Linux kernel 5.3 or newer
* glibc 2.27 or newer

Additionally (see https://lwn.net/Articles/846403/) things don't always work
unless both source and target files are:
* regular files, and
* in the same storage device.

The environment for this experiment was set up as follows:

```
worker@copy-file-test:/$ uname -a
Linux copy-file-test 5.17.12-300.fc36.x86_64 #1 SMP PREEMPT Mon May 30 16:56:53 UTC 2022 x86_64 GNU/Linux

worker@copy-file-test:/$ apt list --installed 2>&1 | grep ^libc6\/
libc6/stable,now 2.31-13+deb11u6 amd64 [installed,automatic]

worker@copy-file-test:/$ carlos@rilke:~/src/copy-file-range-test$ python3 --version
Python 3.11.3
```

First a file was copied to a destination in the same device:

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


## Using `shutil.copyfile()`

Since Python 3.8 the function [shtil.copyfile()][] is able to use more efficient ways of copying files on some platforms.

In this example we copy a file to a destination on a different device:

```
worker@copy-file-test:/$ mount | grep /data/bol-data-layer-data-green-001
bodh1lnxnas-02.ecmwf.int:/mnt/bodh1lnxnas-02_pool/eccharts/datastore_dh1_00 on /data/bol-data-layer-data-green-001 type nfs (rw,relatime,vers=3,rsize=131072,wsize=131072,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=10.120.5.10,mountvers=3,mountport=734,mountproto=udp,local_lock=none,addr=10.120.5.10)

worker@copy-file-test:/$ copy-file --verbose /data/bol-data-layer-data-green-000/fields/20230610_0000/C1E06100000062306001 /data/bol-data-layer-data-green-001/pepe                                                                                                                                                            
Created tmp file /data/bol-data-layer-data-green-001/pepegrwq38lp
copy_file_stdlib: Wrote 7930080066 byte(s)
Renaming /data/bol-data-layer-data-green-001/pepegrwq38lp to /data/bol-data-layer-data-green-001/pepe
```

Here `strace` shows rhe file being copied using the [sendfile(2)][] syscall, thus avoiding kernel- to userspace memory copies:

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


[copy_file_range(2)]: https://man7.org/linux/man-pages/man2/copy_file_range.2.html
[os.copy_file_range()]: https://docs.python.org/3/library/os.html#os.copy_file_range
[os.sendfile()]: https://docs.python.org/3/library/os.html#os.sendfile
[sendfile(2)]: https://man7.org/linux/man-pages/man2/sendfile.2.html
[shutil.copyfile()]: https://docs.python.org/3/library/shutil.html#shutil.copyfile
