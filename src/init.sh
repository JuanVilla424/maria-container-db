#!/bin/bash
# ==============================================
# MariaDB Initialization Script
# Executed during first-time container startup
# ==============================================

set -e

log_info() {
    echo "🐬 [$(date '+%Y-%m-%d %H:%M:%S')] INIT: $*"
}

log_success() {
    echo "✅ [$(date '+%Y-%m-%d %H:%M:%S')] INIT: $*"
}

log_warning() {
    echo "⚠️  [$(date '+%Y-%m-%d %H:%M:%S')] INIT: $*"
}

# Wait for MariaDB to be ready
wait_for_mariadb() {
    log_info "Waiting for MariaDB to be ready..."
    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if mariadb-admin ping -h localhost --silent 2>/dev/null; then
            log_success "MariaDB is ready!"
            return 0
        fi
        ((attempt++))
        log_info "   Attempt ${attempt}/${max_attempts}..."
        sleep 2
    done

    log_warning "MariaDB not ready after ${max_attempts} attempts"
    return 1
}

# Create application database if specified
create_app_database() {
    local db_name="${DATABASE_NAME:-}"
    local app_user="${MARIADB_USER:-}"
    local app_pass="${MARIADB_PASSWORD:-}"

    if [[ -n "$db_name" ]] && [[ "$db_name" != "appdb" ]]; then
        log_info "Creating additional database: $db_name"
        mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" <<-EOSQL
            CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOSQL
        log_success "Database '$db_name' created"
    fi

    # Grant privileges to app user on custom database
    if [[ -n "$app_user" ]] && [[ -n "$db_name" ]]; then
        log_info "Granting privileges to $app_user on $db_name"
        mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" <<-EOSQL
            GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${app_user}'@'%';
            FLUSH PRIVILEGES;
EOSQL
        log_success "Privileges granted"
    fi
}

# Create common indexes for audit tables
create_common_indexes() {
    local db_name="${MARIADB_DATABASE:-appdb}"

    log_info "Creating common table structures..."

    mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" "${db_name}" <<-EOSQL
        -- Audit logs table
        CREATE TABLE IF NOT EXISTS audit_logs (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            user_id BIGINT UNSIGNED,
            action VARCHAR(100) NOT NULL,
            entity_type VARCHAR(100),
            entity_id BIGINT UNSIGNED,
            old_values JSON,
            new_values JSON,
            ip_address VARCHAR(45),
            user_agent VARCHAR(500),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_audit_user (user_id),
            INDEX idx_audit_action (action),
            INDEX idx_audit_entity (entity_type, entity_id),
            INDEX idx_audit_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

        -- Sessions table
        CREATE TABLE IF NOT EXISTS sessions (
            id VARCHAR(128) PRIMARY KEY,
            user_id BIGINT UNSIGNED,
            ip_address VARCHAR(45),
            user_agent VARCHAR(500),
            payload TEXT,
            last_activity INT UNSIGNED,
            expires_at TIMESTAMP,
            INDEX idx_sessions_user (user_id),
            INDEX idx_sessions_expires (expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOSQL

    log_success "Common table structures created"
}

# Execute custom SQL scripts if present
execute_custom_scripts() {
    local scripts_dir="/scripts"

    if [[ -d "$scripts_dir" ]] && [[ "$(ls -A $scripts_dir/*.sql 2>/dev/null)" ]]; then
        log_info "Executing custom SQL scripts..."
        for script in "$scripts_dir"/*.sql; do
            if [[ -f "$script" ]]; then
                log_info "   Running: $(basename $script)"
                mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" < "$script"
            fi
        done
        log_success "Custom scripts executed"
    fi
}

# Main initialization
main() {
    log_info "Starting MariaDB initialization..."

    # The official MariaDB image handles the initial setup
    # This script runs additional customizations

    # Create additional databases and users
    create_app_database

    # Create common indexes (optional)
    if [[ "${CREATE_COMMON_TABLES:-false}" == "true" ]]; then
        create_common_indexes
    fi

    # Execute custom scripts
    execute_custom_scripts

    log_success "MariaDB initialization completed!"
}

main "$@"
