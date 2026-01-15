ARG STACK_VERSION=11.4

FROM mariadb:${STACK_VERSION}

USER root

# Install system dependencies including ECS utilities
RUN apt-get update && apt-get install --no-install-recommends -y \
    locales \
    git \
    python3 \
    python3-pip \
    python3-venv \
    wget \
    gnupg \
    ca-certificates \
    openssl \
    curl \
    jq \
    rsyslog \
    logrotate \
    supervisor \
    procps \
    net-tools \
    dnsutils \
    telnet \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install ECS CLI for container orchestration
RUN curl -Lo /usr/local/bin/ecs-cli \
    https://amazon-ecs-cli.s3.amazonaws.com/ecs-cli-linux-amd64-latest \
    && chmod +x /usr/local/bin/ecs-cli

# Locale configuration
ARG LANG=es_CO.UTF-8
ARG LC_ALL=es_CO.UTF-8

RUN sed -i "s/# ${LANG} UTF-8/${LANG} UTF-8/" /etc/locale.gen \
    && locale-gen ${LANG} \
    && echo "LANG=${LANG}" > /etc/default/locale \
    && echo "LC_ALL=${LC_ALL}" >> /etc/default/locale

ENV LANG=${LANG}
ENV LC_ALL=${LC_ALL}

# Create required directories
RUN mkdir -p /docker-entrypoint-initdb.d \
    && mkdir -p /bootstrapping \
    && mkdir -p /scripts \
    && mkdir -p /var/log/mysql \
    && mkdir -p /etc/mysql/ssl \
    && mkdir -p /backup \
    && mkdir -p /var/run/mysqld \
    && mkdir -p /var/lib/mysql-files \
    && mkdir -p /opt/secrets_manager/src \
    && mkdir -p /opt/backups/src \
    && mkdir /logs

# Create Python virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV

# Update PATH to use the virtual environment
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Upgrade pip in virtual environment
RUN pip install --upgrade pip

# Preserve original MariaDB entrypoint before overwriting
RUN cp /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint-original.sh

# Copy MariaDB core files
COPY src/init.sh /docker-entrypoint-initdb.d/
COPY src/bootstrap.py /bootstrapping/
COPY src/mariadb.cnf /etc/mysql/conf.d/custom.cnf
COPY src/docker-entrypoint.sh /usr/local/bin/
COPY requirements.txt /opt/

# Install Python dependencies in virtual environment
RUN pip install --no-cache-dir -r /opt/requirements.txt

# Configure basic log rotation
RUN echo '/var/log/mysql/*.log {\n\
    daily\n\
    missingok\n\
    rotate 7\n\
    compress\n\
    notifempty\n\
    create 0644 mysql mysql\n\
    postrotate\n\
        /usr/bin/mariadb-admin flush-logs 2>/dev/null || true\n\
    endscript\n\
}' > /etc/logrotate.d/mariadb

# Update Python scripts shebangs to use virtual environment
RUN sed -i '1s|.*|#!/opt/venv/bin/python3|' /bootstrapping/bootstrap.py

# Set executable permissions
RUN chmod +x /docker-entrypoint-initdb.d/init.sh \
    && chmod +x /bootstrapping/bootstrap.py \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# Set ownership and permissions
RUN chown -R mysql:mysql \
    /var/log/mysql \
    /scripts \
    /bootstrapping \
    /var/lib/mysql \
    /var/lib/mysql-files \
    /backup \
    /var/run/mysqld \
    /logs \
    /opt/venv \
    /opt/secrets_manager \
    /opt/backups

# Create health check script that uses the virtual environment
RUN echo '#!/bin/bash\nexport PATH="/opt/venv/bin:$PATH"\nmariadb-admin ping -h localhost --silent > /dev/null 2>&1' > /usr/local/bin/health-check \
    && chmod +x /usr/local/bin/health-check

USER mysql

EXPOSE 3306

# Health check for ECS
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/health-check

ENTRYPOINT ["docker-entrypoint.sh"]
