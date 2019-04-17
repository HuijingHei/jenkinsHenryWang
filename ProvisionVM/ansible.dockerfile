FROM fedora:latest

ARG ANSIBLEDIR=/ansible

RUN dnf -y install ansible \
    && dnf -y install openssh-server \
    && dnf clean all \
    && mkdir -p ${ANSIBLEDIR} \
    && chmod 777 ${ANSIBLEDIR}

ENV ANSIBLE_HOST_KEY_CHECKING false
ENV ANSIBLE_RETRY_FILES_ENABLED false
ENV ANSIBLE_SSH_PIPELINING True

COPY playbook/ansible.pub /root/.ssh/id_rsa.pub
COPY playbook/ansible /root/.ssh/id_rsa

WORKDIR ${ANSIBLEDIR}

#ENTRYPOINT ["ansible-playbook"]
