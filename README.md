Unprivileged LXC containers on debian stretch
=============================================
In general LXC should be considered [unsafe](https://stgraber.org/2014/01/17/lxc-1-0-unprivileged-containers/) as the root user in a container is the same uid 0 as the root user on the host. If he somehow gets access /proc, /sys or /dev, he might escape the container and get root access to the host.

Since the kernel version 2.2 Linux supports [capabilities](http://man7.org/linux/man-pages/man7/capabilities.7.html). These divide superuser privileges into distinct units which may be associated indepently.
Capabilities were the first security features added to LXC. One may configure them per container using the following options:
```
lxc.cap.drop
lxc.cap.keep
```

Since version 1.0 LXC supports using unprivileged containers which greatly enhances container [capsulation](https://linuxcontainers.org/lxc/getting-started/).
Unprivileged LXC containers use user namespaces to map the uids and gids to a new range.
That means uid 0 in the container is mapped to e.g. uid 100000 on the host.
Therefore he would become the user nobody on the host if he manages to escape the container.


## Debian stretch
By default debian uses privileged LXC containers. But it supports [unprivileged](https://wiki.debian.org/LXC#Unprivileged_container) ones, too.
Unprivileged containers may be started as normal user.
But if you want to start them at boot, it is suggested to start them as root.
Here is how that works:

First we need to make sure, the required software is installed.
```
apt install lxc libvirt0 libpam-cgroup libpam-cgfs bridge-utils
```

After that we need to activate user namespaces.
```
echo "kernel.unprivileged_userns_clone=1" > /etc/sysctl.d/80-lxc-userns.conf
sudo sysctl --system
```

Debian does not configure username space ranges for the root user. So we have to assign a range by hand.
First you should check the used ranges by:
```
cat  /etc/s*id
```

After that you may assign the root user a new range. E.g. by:
```
usermod --add-subuids 1258512-1324047 root
usermod --add-subgids 1258512-1324047 root
```


Then adjust the default configuration of containers.
As privileged and unprivileged containers may run side by side you should backup your old configuration:
```
cp /etc/lxc/default.conf /etc/lxc/default-privileged.conf
cat <<EOF >> /etc/lxc/default.conf

## Unprivileged containers
lxc.id_map = u 0 1258512 65536
lxc.id_map = g 0 1258512 65536
EOF
```

The next three lines show how you create an unprivileged container, start it and destroy it again:
```
lxc-create -n unpriv -t download -- --dist debian --release stretch --arch amd64

lxc-start -d -n unpriv
lxc-stop -n unpriv
lxc-destroy -n unpriv
```


## Convert privileged containers to unprivileged
If you are like me and are using LXC containers since years, you probably have a lot of privileged containers you might want to convert to unprivileged ones.
Therefore it is needed to adjust the user and group ids of all files in the container.
Luckily the people of LXD wrote a tool for this: fuidshift

### Get fuidshift
Unfortunatly fuidshift is not packaged in debian. So we have to compile it from source.
But as it is go, you may simply deploy the binary by coping it.
There is no need to compile it on every server.
```
go get -v -x github.com/lxc/lxd/fuidshift
scp go/bin/fuidshift root@host:
```

### Stop & backup container
Of course you need to stop the container before converting it.
And a backup is always recommended.
```
lxc-stop -n stretch
tar -czf /root/backup-lxc/stretch.tar.gz /var/lib/lxc/stretch/
```
Just in case you need to restore the backup, this is your command.
```
tar --numeric-owner -xzf /root/backup-lxc/stretch.tar.gz -C /
```

### Shift user and group ids
Now it is time to call fuidshift:
```
./fuidshift /var/lib/lxc/stretch/rootfs b:0:1258512:65536
```
Furthermore you need to adjust the owner of the containers directory:
```
chown 1258512:1258512 /var/lib/lxc/stretch/
```

The last step is to add user namespaces to the containers configuration
```
cat <<EOF >> /var/lib/lxc/stretch/config

## Unprivileged containers
lxc.include = /usr/share/lxc/config/debian.userns.conf
lxc.id_map = u 0 1258512 65536
lxc.id_map = g 0 1258512 65536
EOF
```

Now it is time to start the converted container again.
```
lxc-start -d -n stretch
```

As I had to convert two handful of containers, I wrote a little bash [script](convert-lxc-container-to-unprivileged.sh) automating the steps above.
And yes it is ugly, but I checked in the fuidshift amd64 binary.
So I only needed to checkout this repo and have everything in place to convert the containers on my servers.


# Privileged containers
Restricting the rights of a container reduces the possibilities to use it.
E.g. ```deboostrap``` does not run in an unprivileged container.
You may still create and use privileged containers on the same host.
```
lxc-create -n sid-privileged --config /etc/lxc/default-privileged.conf -t download -- --dist debian --release sid --arch amd64
```


# AppArmor
AppArmor will be enabled by default in [buster](https://wiki.debian.org/AppArmor/Progress). But it makes sense to [enable](https://wiki.debian.org/AppArmor/HowToUse) it in stretch, too.
```
apt install apparmor apparmor-utils
mkdir /etc/default/grub.d
echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=1 security=apparmor"' | sudo tee /etc/default/grub.d/apparmor.cfg
update-grub
```

Update the default config for AppArmor
```
cat <<EOF >> /etc/lxc/default.conf

## AppArmor stretch
lxc.aa_allow_incomplete = 1
EOF

cat <<EOF >> /etc/lxc/default-privileged.conf

## AppArmor stretch
lxc.aa_allow_incomplete = 1
EOF
```

Of course we need to update the config of every container, too.
