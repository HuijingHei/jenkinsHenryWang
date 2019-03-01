#!/bin/bash

podman build -t ansible .
podman run --name test -d ansible --version
CID=`podman ps | awk 'NR > 1 {print $1; exit}'`
podman cp $CID:/root/.ssh/id_rsa.pub /root/
podman rm test


podman run --privileged=true --name test1 --rm -it ansible ansible-playbook test.yml
