#!/bin/bash

## exit if an error occurs or on unset variables
set -eu -o pipefail

declare -r USAGE="Usage example: $0 container 1258512"

declare -r CONTAINER=${1?${USAGE}}
declare -r USERNS_START=${1?${USAGE}}


declare -r LXC_PATH=${LXC_PATH:-"/var/lib/lxc"}
declare -r BACKUP_DIR=${BACKUP_DIR:-"/root/backup-lxc"}
declare -r CONTAINER_BACKUP="${BACKUP_DIR}/${CONTAINER}-$(date +%Y%m%d-%H%M%S).tar.gz"

if [ $(id -u) != 0 ] ; then
    echo "you must be root to execute this script"
    exit 1
fi

if [ ! -d "${LXC_PATH}/${CONTAINER}/" ] ; then
    echo "container does not exist: \"${LXC_PATH}/${CONTAINER}/\""
    exit 1
fi



echo "stop container \"${CONTAINER}\""
lxc-stop -n "${CONTAINER}"



echo "create a backup: \"${CONTAINER_BACKUP}\""
mkdir -p "${BACKUP_DIR}"
tar -czf "${CONTAINER_BACKUP}" "${LXC_PATH}/${CONTAINER}"
echo "you may restore it with: tar --numeric-owner -xzf ${CONTAINER_BACKUP} -C /"



echo "converting file system"
fuidshift "${LXC_PATH}/${CONTAINER}/rootfs" b:0:"${USERNS_START}:65536"
chown "${USERNS_START}:${USERNS_START}" "${LXC_PATH}/${CONTAINER}"



echo "updating config"
cat <<EOF >> "${LXC_PATH}/${CONTAINER}/config"

## Unprivileged containers
lxc.include = /usr/share/lxc/config/debian.userns.conf
lxc.id_map = u 0 1258512 65536
lxc.id_map = g 0 1258512 65536
EOF



echo "start container"
lxc-start -d -n "${CONTAINER}"
lxc-ls --fancy
