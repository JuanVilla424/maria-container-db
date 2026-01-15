# 🐬 Maria Container DB

![MariaDB](https://img.shields.io/badge/MariaDB-003545?logo=mariadb&logoColor=fff)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=fff)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=fff)
![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=fff)
![Status](https://img.shields.io/badge/Status-Development-blue.svg)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A production-ready MariaDB container with InnoDB optimization, authentication, and advanced configuration options.

<img src="https://mariadb.com/wp-content/uploads/2019/11/mariadb-logo-vert_blue-transparent.png" width="112" alt="MariaDB">

## 📚 Table of Contents

- [🚀 Quick Start](#-quick-start)
- [📁 Project Structure](#-project-structure)
- [🔧 Features](#-features)
- [⚙️ Configuration](#-configuration)
- [🏗️ Build Process](#-build-process)
- [🔐 Security](#-security)
- [📊 Monitoring](#-monitoring)
- [🚨 Troubleshooting](#-troubleshooting)
- [🔄 Backup & Recovery](#-backup--recovery)
- [🚀 Production Deployment](#-production-deployment)
- [🤝 Contributing](#-contributing)
- [📫 Contact](#-contact)
- [📜 License](#-license)

## 🚀 Quick Start

1. **Clone and setup**:

   ```bash
   git clone https://github.com/JuanVilla424/maria-container-db.git
   cd maria-container-db
   cp .env.example .env
   python -m venv .venv
   source .venv/bin/activate  # Linux/MacOS
   # .\.venv\Scripts\Activate.ps1  # Windows
   pip install --upgrade pip
   pip install -r requirements.txt
   ```

2. **Set Password** (Optional)

   Sync submodule to set password on `.env` file.

   ```bash
   git submodule update --remote --merge
   python scripts/init_security_config/main.py --files .env
   ```

3. **Configure environment**:

   Edit `.env` file with your settings:

   ```bash
   MARIADB_ROOT_PASSWORD=your-secure-password
   MARIADB_USER=appuser
   MARIADB_PASSWORD=app-user-password
   MARIADB_DATABASE=appdb
   MARIADB_PORT=3306
   ```

4. **Build MariaDB**

   ```bash
   docker compose build --build-arg STACK_VERSION=11.4 --build-arg LANG=es_CO.UTF-8
   ```

5. **Start MariaDB**:

   ```bash
   docker compose up -d
   ```

6. **Connect**:
   ```bash
   mariadb -h 127.0.0.1 -P 3306 -u root -p
   ```

## 📁 Project Structure

```
├── src/
│   ├── docker-entrypoint.sh    # Main entrypoint with dynamic config
│   ├── mariadb.cnf             # MariaDB configuration template
│   ├── init.sh                 # Advanced initialization script
│   └── bootstrap.py            # Python bootstrap for health checks
├── helpers/                    # helpers directory
│  ├── backups                  # Backups MariaDB helper
│  └── secrets_manager          # Secrets Manager MariaDB helper
├── docker-compose.yml          # Production Docker Compose
├── Dockerfile                  # Optimized multi-stage build
├── .env.example                # Environment variables template
└── README.md                   # Readme File
```

## 🔧 Features

### Core Features

- ✅ **MariaDB 11.4** with InnoDB storage engine
- ✅ **Binary Logging** configured for replication/PITR
- ✅ **Authentication** with secure password policies
- ✅ **Dynamic configuration** via environment variables
- ✅ **Production-ready** performance settings
- ✅ **Colombian locale** support (configurable)

### Advanced Features

- ✅ **Git repository integration** for custom scripts
- ✅ **Python bootstrap** for health checks and indexes
- ✅ **Resource limits** and ulimits configuration
- ✅ **Persistent volumes** with host path binding
- ✅ **Health checks** and automatic restarts
- ✅ **Security hardening** with non-privileged user

### Performance Optimizations

- ✅ **InnoDB buffer pool** optimization
- ✅ **Thread pooling** and connection management
- ✅ **Query cache** configuration (disabled by default for 10.1.7+)
- ✅ **Slow query logging** for performance analysis
- ✅ **Connection pooling** (500 max connections default)

## ⚙️ Configuration

### Key Environment Variables

#### Basic MariaDB Configuration

| Variable                | Default   | Description                             |
| ----------------------- | --------- | --------------------------------------- |
| `STACK_VERSION`         | `11.4`    | MariaDB version                         |
| `MARIADB_PORT`          | `3306`    | External port mapping                   |
| `MARIADB_DATABASE`      | `appdb`   | Initial database name                   |
| `MARIADB_ROOT_PASSWORD` | -         | Root password (18+ chars with specials) |
| `MARIADB_USER`          | `appuser` | Application user                        |
| `MARIADB_PASSWORD`      | -         | Application user password               |
| `DATABASE_NAME`         | `appdb`   | Application database name               |

#### Network Configuration

| Variable                      | Default   | Description                    |
| ----------------------------- | --------- | ------------------------------ |
| `MARIADB_BIND_ADDRESS`        | `0.0.0.0` | IP address to bind             |
| `MARIADB_MAX_CONNECTIONS`     | `500`     | Maximum concurrent connections |
| `MARIADB_CONNECT_TIMEOUT`     | `10`      | Connection timeout (seconds)   |
| `MARIADB_WAIT_TIMEOUT`        | `28800`   | Wait timeout (seconds)         |
| `MARIADB_INTERACTIVE_TIMEOUT` | `28800`   | Interactive timeout (seconds)  |

#### InnoDB Storage Engine Configuration

| Variable                                 | Default    | Description                     |
| ---------------------------------------- | ---------- | ------------------------------- |
| `MARIADB_INNODB_BUFFER_POOL_SIZE`        | `1G`       | InnoDB buffer pool size         |
| `MARIADB_INNODB_LOG_FILE_SIZE`           | `256M`     | InnoDB log file size            |
| `MARIADB_INNODB_LOG_BUFFER_SIZE`         | `64M`      | InnoDB log buffer size          |
| `MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT` | `1`        | Flush log at transaction commit |
| `MARIADB_INNODB_FLUSH_METHOD`            | `O_DIRECT` | InnoDB flush method             |
| `MARIADB_INNODB_FILE_PER_TABLE`          | `ON`       | Separate file per table         |
| `MARIADB_INNODB_IO_CAPACITY`             | `2000`     | I/O capacity                    |
| `MARIADB_INNODB_IO_CAPACITY_MAX`         | `4000`     | Max I/O capacity                |

#### Security Configuration

| Variable                    | Default | Description             |
| --------------------------- | ------- | ----------------------- |
| `MARIADB_SECURE_AUTH`       | `ON`    | Enable secure auth      |
| `MARIADB_LOCAL_INFILE`      | `OFF`   | Disable LOAD DATA LOCAL |
| `MARIADB_SKIP_NAME_RESOLVE` | `ON`    | Skip DNS resolution     |
| `MARIADB_SYMBOLIC_LINKS`    | `OFF`   | Disable symbolic links  |

#### Binary Logging (Replication/PITR)

| Variable                   | Default     | Description               |
| -------------------------- | ----------- | ------------------------- |
| `MARIADB_LOG_BIN`          | `mysql-bin` | Binary log file prefix    |
| `MARIADB_BINLOG_FORMAT`    | `ROW`       | Binary log format         |
| `MARIADB_EXPIRE_LOGS_DAYS` | `7`         | Days to keep bin logs     |
| `MARIADB_MAX_BINLOG_SIZE`  | `512M`      | Max binary log size       |
| `MARIADB_SYNC_BINLOG`      | `1`         | Sync binlog to disk       |
| `MARIADB_SERVER_ID`        | `1`         | Server ID for replication |

#### Logging Configuration

| Variable                      | Default                    | Description              |
| ----------------------------- | -------------------------- | ------------------------ |
| `MARIADB_SLOW_QUERY_LOG`      | `ON`                       | Enable slow query log    |
| `MARIADB_SLOW_QUERY_LOG_FILE` | `/var/log/mysql/slow.log`  | Slow query log path      |
| `MARIADB_LONG_QUERY_TIME`     | `2`                        | Slow query threshold (s) |
| `MARIADB_LOG_ERROR`           | `/var/log/mysql/error.log` | Error log path           |
| `MARIADB_LOG_WARNINGS`        | `2`                        | Warning log level        |

#### Container Resource Configuration

| Variable                 | Default | Description           |
| ------------------------ | ------- | --------------------- |
| `CONTAINER_CPU_LIMIT`    | `2`     | CPU cores limit       |
| `CONTAINER_MEMORY_LIMIT` | `4G`    | Memory limit          |
| `CONTAINER_SWAP_LIMIT`   | `1G`    | Swap limit            |
| `CONTAINER_PIDS_LIMIT`   | `4096`  | Process limit         |
| `MARIADB_ULIMIT_NOFILE`  | `65535` | File descriptor limit |
| `MARIADB_ULIMIT_NPROC`   | `65535` | Process limit         |

#### Galera Cluster Configuration (Optional)

| Variable                        | Default          | Description           |
| ------------------------------- | ---------------- | --------------------- |
| `MARIADB_GALERA_CLUSTER`        | `false`          | Enable Galera cluster |
| `MARIADB_WSREP_CLUSTER_NAME`    | `galera_cluster` | Cluster name          |
| `MARIADB_WSREP_CLUSTER_ADDRESS` | `gcomm://`       | Cluster address       |
| `MARIADB_WSREP_NODE_NAME`       | `node1`          | Node name             |
| `MARIADB_WSREP_SST_METHOD`      | `mariabackup`    | SST method            |

#### Health Check Configuration

| Variable                            | Default | Description                 |
| ----------------------------------- | ------- | --------------------------- |
| `MARIADB_HEALTH_CHECK_INTERVAL`     | `30s`   | Health check interval       |
| `MARIADB_HEALTH_CHECK_TIMEOUT`      | `10s`   | Health check timeout        |
| `MARIADB_HEALTH_CHECK_RETRIES`      | `3`     | Health check retry attempts |
| `MARIADB_HEALTH_CHECK_START_PERIOD` | `60s`   | Health check startup period |

#### AWS Configuration

| Variable                | Default     | Description                 |
| ----------------------- | ----------- | --------------------------- |
| `AWS_REGION`            | `us-east-1` | AWS region                  |
| `AWS_ACCESS_KEY_ID`     | -           | AWS access key ID           |
| `AWS_SECRET_ACCESS_KEY` | -           | AWS secret access key       |
| `ENVIRONMENT_TYPE`      | `dev`       | Environment type            |
| `USE_SECRETS_MANAGER`   | `false`     | Use AWS Secrets Manager     |
| `SECRET_NAME`           | -           | Secrets Manager secret name |

### Volume Configuration

The container uses bind mounts for persistent data:

```yaml
volumes:
  - ./data:/var/lib/mysql # Database files
  - ./logs:/var/log/mysql # Log files
  - ./backup:/backup # Backup directory
```

## 🏗️ Build Process

The entrypoint performs these steps:

1. **Environment Detection**: Detects ECS, EC2, Kubernetes, or Docker
2. **Credential Management**: AWS Secrets Manager or environment variables
3. **Directory Setup**: Creates required directories
4. **Permissions**: Sets MySQL user ownership
5. **Configuration**: Applies environment variables to config
6. **First-Time Init**: Creates database and users
7. **Script Execution**: Runs custom initialization scripts
8. **Bootstrap**: Executes Python health checks
9. **Production Start**: Launches MariaDB with final configuration

## 🔐 Security

### Authentication

- Root user with strong password
- Application user with limited privileges
- Skip name resolve for faster connections

### Container Security

- Non-privileged `mysql` user
- `no-new-privileges` security option
- Secure tmpfs mount
- Resource limits enforced

### Network Security

- Bind to specific interfaces only
- Configurable port mapping
- Isolated Docker network
- Local infile disabled

## 📊 Monitoring

### Health Checks

Built-in health check every 30 seconds:

```bash
mariadb-admin ping -h localhost --silent
```

### Log Monitoring

Logs are automatically managed:

- Error log: `/var/log/mysql/error.log`
- Slow query log: `/var/log/mysql/slow.log`
- General log: `/var/log/mysql/general.log` (disabled by default)

### Performance Monitoring

Use these queries for monitoring:

```sql
-- Show process list
SHOW PROCESSLIST;

-- Show InnoDB status
SHOW ENGINE INNODB STATUS;

-- Show global status
SHOW GLOBAL STATUS;

-- Show variables
SHOW VARIABLES LIKE 'innodb%';
```

## 🚨 Troubleshooting

### Common Issues

**Container won't start**:

```bash
docker-compose logs mariadb
```

**Authentication failures**:

- Verify credentials in `.env`
- Check user permissions

**Performance issues**:

- Monitor InnoDB buffer pool hit ratio
- Check slow query logs
- Adjust `MARIADB_INNODB_BUFFER_POOL_SIZE`

**Connection issues**:

- Verify port mapping: `MARIADB_PORT=3306`
- Check firewall settings
- Verify skip-name-resolve setting

### Debug Commands

Connect to container:

```bash
docker-compose exec mariadb bash
```

Check server status:

```bash
mariadb-admin -u root -p status
```

View configuration:

```bash
mariadb -u root -p -e "SHOW VARIABLES"
```

## 🔄 Backup & Recovery

### Automated Backups

Backup Helper works as a Daemon with configurable schedules.

```bash
# Backup Settings in .env
BACKUP_ENABLED=true
BACKUP_DIRECTORY=/backup
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_COMPRESSION=true
BACKUP_COMPRESSION_ALGORITHM=zstd
```

### Manual Backup

```bash
docker-compose exec mariadb mariadb-dump -u root -p --all-databases > backup.sql
```

### Restore

```bash
docker-compose exec -T mariadb mariadb -u root -p < backup.sql
```

## 🚀 Production Deployment

### ECS Deployment

The configuration is optimized for AWS ECS with:

- Resource limits for task definitions
- Health checks for load balancers
- Logging configuration for CloudWatch

### Scaling

- Vertical: Increase `CONTAINER_CPU_LIMIT` and `CONTAINER_MEMORY_LIMIT`
- Horizontal: Configure Galera Cluster for multi-node setup

### Monitoring Integration

- CloudWatch logs via awslogs driver
- Prometheus metrics via MariaDB exporter
- Health endpoint for load balancers

## 🤝 Contributing

**Contributions are welcome! To contribute to this repository, please follow these steps**:

1. **Fork the Repository**

2. **Create a Feature Branch**

   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Commit Your Changes**

   ```bash
   git commit -m "feat(<scope>): your feature commit message - lower case"
   ```

4. **Push to the Branch**

   ```bash
   git push origin feature/your-feature-name
   ```

5. **Open a Pull Request into** `dev` **branch**

Please ensure your contributions adhere to the Code of Conduct and Contribution Guidelines.

## 📫 Contact

For any inquiries or support, please open an issue or contact [r6ty5r296it6tl4eg5m.constant214@passinbox.com](mailto:r6ty5r296it6tl4eg5m.constant214@passinbox.com).

---

## 📜 License

© 2026 Quipux. All rights reserved. Unauthorized use, reproduction, or distribution is strictly prohibited.
