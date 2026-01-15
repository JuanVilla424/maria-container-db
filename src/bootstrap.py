#!/opt/venv/bin/python3
"""
MariaDB Bootstrap Script
Handles health checks, index creation, and initialization tasks
"""

import os
import sys
import time
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="🐬 [%(asctime)s] %(levelname)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


def get_mariadb_connection():
    """Create MariaDB connection using PyMySQL"""
    try:
        import pymysql
    except ImportError:
        logger.error("PyMySQL not installed. Run: pip install pymysql")
        return None

    host = os.getenv("MARIADB_HOST", "localhost")
    port = int(os.getenv("MARIADB_PORT", "3306"))
    user = os.getenv("MARIADB_ROOT_USERNAME", "root")
    password = os.getenv("MARIADB_ROOT_PASSWORD", "")
    database = os.getenv("MARIADB_DATABASE", "appdb")

    try:
        connection = pymysql.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=database,
            charset="utf8mb4",
            cursorclass=pymysql.cursors.DictCursor,
            connect_timeout=30,
        )
        logger.info(f"Connected to MariaDB at {host}:{port}")
        return connection
    except Exception as e:
        logger.error(f"Failed to connect to MariaDB: {e}")
        return None


def check_health():
    """Perform health check on MariaDB"""
    connection = get_mariadb_connection()
    if not connection:
        return False

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 as health_check")
            result = cursor.fetchone()
            if result and result.get("health_check") == 1:
                logger.info("✅ Health check passed")
                return True
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return False
    finally:
        connection.close()

    return False


def wait_for_mariadb(max_attempts=30, delay=2):
    """Wait for MariaDB to be ready"""
    logger.info("Waiting for MariaDB to be ready...")

    for attempt in range(1, max_attempts + 1):
        if check_health():
            logger.info(f"MariaDB ready after {attempt} attempt(s)")
            return True
        logger.info(f"Attempt {attempt}/{max_attempts} - MariaDB not ready yet...")
        time.sleep(delay)

    logger.error(f"MariaDB not ready after {max_attempts} attempts")
    return False


def create_indexes():
    """Create common indexes for performance optimization"""
    connection = get_mariadb_connection()
    if not connection:
        logger.error("Cannot create indexes - no database connection")
        return False

    indexes = [
        # Users table indexes
        ("users", "idx_users_email", "email"),
        ("users", "idx_users_username", "username"),
        ("users", "idx_users_created", "created_at"),
        # Sessions table indexes
        ("sessions", "idx_sessions_user_id", "user_id"),
        ("sessions", "idx_sessions_expires", "expires_at"),
        # Audit logs indexes
        ("audit_logs", "idx_audit_timestamp", "created_at"),
        ("audit_logs", "idx_audit_user", "user_id"),
        ("audit_logs", "idx_audit_action", "action"),
    ]

    try:
        with connection.cursor() as cursor:
            for table, index_name, column in indexes:
                try:
                    # Check if table exists
                    cursor.execute(f"SHOW TABLES LIKE '{table}'")
                    if not cursor.fetchone():
                        logger.info(f"Table '{table}' does not exist, skipping index")
                        continue

                    # Check if index exists
                    cursor.execute(
                        f"SHOW INDEX FROM {table} WHERE Key_name = %s", (index_name,)
                    )
                    if cursor.fetchone():
                        logger.info(f"Index '{index_name}' already exists on '{table}'")
                        continue

                    # Create index
                    cursor.execute(f"CREATE INDEX {index_name} ON {table} ({column})")
                    logger.info(
                        f"✅ Created index '{index_name}' on '{table}.{column}'"
                    )

                except Exception as e:
                    logger.warning(f"Could not create index '{index_name}': {e}")

        connection.commit()
        logger.info("Index creation completed")
        return True

    except Exception as e:
        logger.error(f"Index creation failed: {e}")
        return False
    finally:
        connection.close()


def get_server_status():
    """Get MariaDB server status information"""
    connection = get_mariadb_connection()
    if not connection:
        return None

    try:
        with connection.cursor() as cursor:
            # Get version
            cursor.execute("SELECT VERSION() as version")
            version = cursor.fetchone()

            # Get uptime
            cursor.execute("SHOW STATUS LIKE 'Uptime'")
            uptime = cursor.fetchone()

            # Get connections
            cursor.execute("SHOW STATUS LIKE 'Threads_connected'")
            threads = cursor.fetchone()

            # Get InnoDB buffer pool
            cursor.execute("SHOW STATUS LIKE 'Innodb_buffer_pool_pages_total'")
            buffer_pool = cursor.fetchone()

            status = {
                "version": version.get("version") if version else "unknown",
                "uptime_seconds": uptime.get("Value") if uptime else 0,
                "threads_connected": threads.get("Value") if threads else 0,
                "buffer_pool_pages": buffer_pool.get("Value") if buffer_pool else 0,
                "timestamp": datetime.now().isoformat(),
            }

            logger.info("📊 MariaDB Status:")
            logger.info(f"   Version: {status['version']}")
            logger.info(f"   Uptime: {status['uptime_seconds']}s")
            logger.info(f"   Connected threads: {status['threads_connected']}")
            logger.info(f"   Buffer pool pages: {status['buffer_pool_pages']}")

            return status

    except Exception as e:
        logger.error(f"Failed to get server status: {e}")
        return None
    finally:
        connection.close()


def main():
    """Main bootstrap function"""
    logger.info("🐬 MariaDB Bootstrap Starting...")
    logger.info(f"   Environment: {os.getenv('DEPLOYMENT_ENVIRONMENT', 'unknown')}")
    logger.info(f"   Database: {os.getenv('MARIADB_DATABASE', 'appdb')}")

    # Wait for MariaDB to be ready
    timeout = int(os.getenv("MARIADB_BOOTSTRAP_TIMEOUT", 300))
    max_attempts = timeout // 2

    if not wait_for_mariadb(max_attempts=max_attempts):
        logger.error("Bootstrap failed - MariaDB not available")
        sys.exit(1)

    # Get server status
    get_server_status()

    # Create indexes if enabled
    if os.getenv("CREATE_INDEXES", "false").lower() == "true":
        create_indexes()

    logger.info("✅ Bootstrap completed successfully!")
    sys.exit(0)


if __name__ == "__main__":
    main()
