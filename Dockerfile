FROM python:3.11

RUN \
  set -eux \
  && groupadd -g 1211 worker \
  && useradd -g worker -u 3570 -s /bin/bash -m worker

RUN \
  set -eux \
  && apt-get update --yes \
  && apt-get install --yes strace sudo

COPY copy-file /usr/local/bin/

USER worker
