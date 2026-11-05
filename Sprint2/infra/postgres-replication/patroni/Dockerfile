FROM postgres:17-bookworm

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        python3-dev \
        build-essential \
        libpq-dev \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/patroni \
    && /opt/patroni/bin/pip install --no-cache-dir \
        "patroni[etcd3]" \
        "psycopg2-binary>=2.9"

ENV PATH="/opt/patroni/bin:${PATH}"

COPY patroni-entrypoint.sh /usr/local/bin/patroni-entrypoint.sh
COPY patroni-post-bootstrap.sh /usr/local/bin/patroni-post-bootstrap.sh
COPY patroni.yml.tmpl /etc/patroni/patroni.yml.tmpl

RUN chmod +x \
    /usr/local/bin/patroni-entrypoint.sh \
    /usr/local/bin/patroni-post-bootstrap.sh

ENTRYPOINT ["/usr/local/bin/patroni-entrypoint.sh"]
