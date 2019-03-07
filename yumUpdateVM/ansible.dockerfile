FROM fedora:latest
RUN dnf -y install ansible && \
    dnf -y install openssh-server && \
    dnf clean all

RUN mkdir /ansible
RUN ssh-keygen -q -m PEM -t rsa -N '' -f /root/.ssh/id_rsa
COPY playbook/vars.yml /ansible/
COPY playbook/yumUpdateVM.yml /ansible
COPY playbook/test.yml /ansible
COPY playbook/hosts /etc/ansible/hosts

ENV ANSIBLE_HOST_KEY_CHECKING false
ENV ANSIBLE_RETRY_FILES_ENABLED false
ENV ANSIBLE_SSH_PIPELINING True

WORKDIR /ansible

ENTRYPOINT ["ansible-playbook"]
