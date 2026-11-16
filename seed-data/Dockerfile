FROM python:3.9-slim

# add apache bench (ab) tool
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    apache2-utils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /seed

COPY . .

# create POST data files with ab friendly formats
RUN python make-data.py

USER 10001
CMD ["/seed/generate-votes.sh"]
