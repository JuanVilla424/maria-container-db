#!/bin/bash
set -e

# ========================================
# ENHANCED MARIADB CONTAINER ENTRYPOINT
# WITH AUTO-CREATING AWS SECRETS MANAGER INTEGRATION
# SUPPORTS BOTH ECS AND ON-PREMISE DEPLOYMENTS
# ========================================

log_info() {
    echo "🐬 [$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "💥 [$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_warning() {
    echo "⚠️  [$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" >&2
}

log_success() {
    echo "✅ [$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# ========================================
# SMART DEPLOYMENT DETECTION
# ========================================

detect_deployment_environment() {
    log_info "Detecting deployment environment..."

    # ECS Detection (Primary)
    if [[ -n "${ECS_CONTAINER_METADATA_URI:-}${ECS_CONTAINER_METADATA_URI_V4:-}" ]]; then
        export DEPLOYMENT_ENVIRONMENT="ECS"
        export USE_SECRETS_MANAGER="${USE_SECRETS_MANAGER:-false}"
        export AWS_REGION="${AWS_REGION:-us-east-1}"

        # Auto-configure secret name if not provided
        if [[ -z "${SECRET_NAME:-}" ]]; then
            local cluster_name=""
            local service_name=""

            # Try to get cluster/service info from ECS metadata
            if [[ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]]; then
                local metadata
                if metadata=$(timeout 5 curl -s "${ECS_CONTAINER_METADATA_URI_V4}/task" 2>/dev/null); then
                    cluster_name=$(echo "$metadata" | grep -o '"Cluster":"[^"]*"' | cut -d'"' -f4 | head -1)
                    service_name=$(echo "$metadata" | grep -o '"ServiceName":"[^"]*"' | cut -d'"' -f4 | head -1)
                fi
            fi

            if [[ -n "$cluster_name" ]] && [[ -n "$service_name" ]]; then
                export SECRET_NAME="ecs/${cluster_name}/${service_name}/mariadb/credentials"
            else
                export SECRET_NAME="ecs/mariadb/credentials"
            fi
        fi

        log_success "Environment: ECS"
        log_info "   Auto-configured for AWS ECS"
        log_info "   Secrets Manager: ${USE_SECRETS_MANAGER}"
        log_info "   Secret Name: ${SECRET_NAME}"
        log_info "   AWS Region: ${AWS_REGION}"

    # Kubernetes Detection
    elif [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        export DEPLOYMENT_ENVIRONMENT="KUBERNETES"
        log_success "Environment: Kubernetes"
        log_info "   Using environment variables (K8s secrets recommended)"

    # EC2 Detection (with AWS CLI available)
    elif timeout 3 curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        export DEPLOYMENT_ENVIRONMENT="EC2"
        export USE_SECRETS_MANAGER="${USE_SECRETS_MANAGER:-true}"
        export AWS_REGION="${AWS_REGION:-$(timeout 3 curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo 'us-east-1')}"
        log_success "Environment: EC2"
        log_info "   Auto-enabled Secrets Manager for EC2"
        log_info "   Detected region: ${AWS_REGION}"

    # Docker Detection
    elif [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        export DEPLOYMENT_ENVIRONMENT="DOCKER"
        log_success "Environment: Docker"
        log_info "   On-premise Docker deployment"

    # Local/Bare Metal
    else
        export DEPLOYMENT_ENVIRONMENT="LOCAL"
        log_success "Environment: Local/Bare Metal"
        log_info "   On-premise deployment"
    fi

    export DEPLOYMENT_ENVIRONMENT
}

# ========================================
# ECS-SPECIFIC OPTIMIZATIONS
# ========================================

configure_ecs_environment() {
    if [[ "${DEPLOYMENT_ENVIRONMENT}" != "ECS" ]]; then
        return 0
    fi

    log_info "Applying ECS-specific optimizations..."

    # Set TMPDIR for MariaDB to use writable location
    export TMPDIR="/tmp"
    export HOME="/tmp/mysql"

    # Create temporary directories that are writable
    mkdir -p /tmp/mysql
    chmod 777 /tmp/mysql

    log_success "ECS environment configured"
}

# Function to safely attempt chown operations
safe_chown() {
    local user="$1"
    local group="$2"
    shift 2
    local paths=("$@")

    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            if chown "$user:$group" "$path" 2>/dev/null; then
                log_info "   Changed ownership of $path to $user:$group"
            else
                log_warning "Failed to change ownership of $path (non-critical)"
            fi
        fi
    done
}

# ========================================
# CREDENTIAL MANAGEMENT
# ========================================

validate_aws_basic_access() {
    local region="${AWS_REGION:-us-east-1}"

    log_info "Validating AWS Secrets Manager access..."
    log_info "   Region: ${region}"
    log_info "   Secret: ${SECRET_NAME:-}"

    local aws_test_output
    local aws_test_exit_code
    aws_test_output=$(python -c "import boto3; boto3.client('secretsmanager', region_name='${region}').list_secrets(MaxResults=1); print('AWS credentials OK')" 2>&1)
    aws_test_exit_code=$?

    if [[ $aws_test_exit_code -eq 0 ]]; then
        log_success "AWS Secrets Manager basic access validated"
        return 0
    else
        log_warning "AWS Secrets Manager not accessible"
        return 1
    fi
}

manage_mariadb_credentials() {
    log_info "Managing MariaDB credentials..."

    # Smart defaults based on environment
    case "${DEPLOYMENT_ENVIRONMENT:-DOCKER}" in
        "ECS"|"EC2")
            log_info "   Cloud environment detected - trying AWS Secrets Manager first"
            ;;
        "KUBERNETES")
            log_info "   Kubernetes detected - using environment variables (K8s secrets)"
            ;;
        "DOCKER"|"LOCAL")
            log_info "   On-premise environment - using environment variables"
            ;;
    esac

    # Try AWS Secrets Manager if enabled and available
    if [[ "${USE_SECRETS_MANAGER:-false}" == "true" ]] && [[ -n "${SECRET_NAME:-}" ]]; then
        log_info "Checking AWS Secrets Manager availability..."

        if validate_aws_basic_access; then
            log_info "Attempting to get existing secret..."
            local get_output
            local get_exit_code
            get_output=$(python /opt/secrets_manager/secrets_manager.py get 2>&1)
            get_exit_code=$?

            if [[ $get_exit_code -eq 0 ]]; then
                password=$(echo "$get_output" | grep -i password | cut -d: -f2- | tr -d ' ')
                if [[ -n "$password" ]]; then
                    export MARIADB_ROOT_PASSWORD="$password"
                    export CREDENTIALS_SOURCE="secrets_manager"
                    log_success "Retrieved existing secret from AWS Secrets Manager"
                    return 0
                fi
            fi

            # If get failed, try to create new secret
            log_info "Secret not found, creating new secret..."
            local create_output
            local create_exit_code
            create_output=$(python /opt/secrets_manager/secrets_manager.py create --username "root" 2>&1)
            create_exit_code=$?

            if [[ $create_exit_code -eq 0 ]]; then
                local new_get_output
                new_get_output=$(python /opt/secrets_manager/secrets_manager.py get 2>&1)
                password=$(echo "$new_get_output" | grep -i password | cut -d: -f2- | tr -d ' ')
                if [[ -n "$password" ]]; then
                    export MARIADB_ROOT_PASSWORD="$password"
                    export CREDENTIALS_SOURCE="secrets_manager"
                    log_success "Created new secret in AWS Secrets Manager"
                    return 0
                fi
            fi

            log_error "Failed to get or create credentials from AWS Secrets Manager"
        fi

        log_warning "AWS Secrets Manager not accessible - falling back to environment variables"
    fi

    # Fallback to environment variables
    export CREDENTIALS_SOURCE="environment"

    if [[ -n "${MARIADB_ROOT_PASSWORD:-}" ]]; then
        log_success "Using environment variable password"
        log_info "   Password: [MASKED - ${#MARIADB_ROOT_PASSWORD} characters]"

        if [[ "${DEPLOYMENT_ENVIRONMENT:-}" == "ECS" ]] || [[ "${DEPLOYMENT_ENVIRONMENT:-}" == "EC2" ]]; then
            if [[ ${#MARIADB_ROOT_PASSWORD} -lt 18 ]]; then
                log_warning "Password length (${#MARIADB_ROOT_PASSWORD}) is below recommended minimum (18) for production"
            fi
        fi
    else
        log_error "No password found in environment variables"
        log_info ""
        log_info "SOLUTIONS by environment:"
        case "${DEPLOYMENT_ENVIRONMENT:-}" in
            "ECS")
                log_info "   ECS: Set environment variables in task definition"
                log_info "   OR: Enable Secrets Manager (recommended)"
                ;;
            "KUBERNETES")
                log_info "   K8s: Use Kubernetes secrets"
                ;;
            "DOCKER"|"LOCAL")
                log_info "   Docker: Set MARIADB_ROOT_PASSWORD"
                log_info "           docker run -e MARIADB_ROOT_PASSWORD=pass ..."
                ;;
        esac
        return 1
    fi

    return 0
}

# ========================================
# MARIADB SETUP FUNCTIONS
# ========================================

check_mariadb_prerequisites() {
    log_info "Checking MariaDB prerequisites..."

    # Check if MariaDB binary exists
    if ! command -v mariadbd &> /dev/null && ! command -v mysqld &> /dev/null; then
        log_error "mariadbd/mysqld binary not found"
        return 1
    fi

    # Check if mariadb client exists
    if ! command -v mariadb &> /dev/null && ! command -v mysql &> /dev/null; then
        log_error "mariadb/mysql client not found"
        return 1
    fi

    # Check data directory permissions
    if [[ ! -w "/var/lib/mysql" ]]; then
        log_warning "Data directory /var/lib/mysql may not be writable, will attempt to fix"
    fi

    # Check available disk space (minimum 1GB)
    local available_space
    available_space=$(df /var/lib/mysql 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ $available_space -gt 0 ]] && [[ $available_space -lt 1048576 ]]; then
        log_warning "Low disk space available: $(($available_space / 1024))MB"
    fi

    # Test MariaDB version
    local maria_version
    maria_version=$(mariadbd --version 2>/dev/null || mysqld --version 2>/dev/null || echo "unknown")
    log_info "   MariaDB version: $maria_version"

    log_success "MariaDB prerequisites check completed"
    return 0
}

setup_directories_and_permissions() {
    log_info "Setting up directories and permissions..."

    # Create directories if they don't exist
    local directories=("/var/lib/mysql" "/var/log/mysql" "/backup" "/scripts" "/var/run/mysqld")

    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "   Created directory: $dir"
        fi
    done

    # Set ownership if mysql user exists
    if id "mysql" &>/dev/null; then
        safe_chown "mysql" "mysql" "${directories[@]}"
        log_success "Permissions assignment completed"
    else
        log_warning "MySQL user does not exist. Skipping permission change"
    fi
}

generate_mariadb_config() {
    log_info "Generating MariaDB configuration from environment variables..."

    # The configuration is already handled by /etc/mysql/conf.d/custom.cnf
    # which is copied during docker build

    log_success "MariaDB configuration ready"
}

start_backup_daemon() {
    local enable_backups="${BACKUP_ENABLED:-true}"

    if [[ "$enable_backups" == "true" ]]; then
        log_info "Starting automated backup daemon..."

        if [[ -f "/opt/backups/backups.py" ]]; then
            cd /opt/backups
            python backups.py daemon &
            local daemon_pid=$!

            sleep 2

            if kill -0 $daemon_pid 2>/dev/null; then
                log_success "Backup daemon started successfully (PID: $daemon_pid)"
                echo $daemon_pid > /var/run/mysqld/backup-daemon.pid
            else
                log_error "Failed to start backup daemon"
                return 1
            fi
        else
            log_warning "Backup system not found, skipping daemon startup"
            return 1
        fi
    else
        log_info "Automated backups disabled (BACKUP_ENABLED=false)"
    fi

    return 0
}

print_deployment_summary() {
    log_info ""
    log_info "MariaDB Container Deployment Summary:"
    log_info "   Environment: ${DEPLOYMENT_ENVIRONMENT:-unknown}"
    log_info "   Credentials: ${CREDENTIALS_SOURCE:-environment}"
    log_info "   MariaDB Version: ${STACK_VERSION:-11.4}"

    if [[ "${CREDENTIALS_SOURCE:-}" == "secrets_manager" ]]; then
        log_info "   AWS Secrets Manager: enabled"
        log_info "   Secret: ${SECRET_NAME:-not-set}"
        log_info "   Region: ${AWS_REGION:-not-set}"
    else
        log_info "   Environment variables: used"
        if [[ "${DEPLOYMENT_ENVIRONMENT:-}" == "ECS" ]] || [[ "${DEPLOYMENT_ENVIRONMENT:-}" == "EC2" ]]; then
            log_info "   Consider enabling Secrets Manager for production"
        fi
    fi

    log_info "   Root user: root"
    log_info "   App user: ${MARIADB_USER:-appuser}"
    log_info "   Database: ${MARIADB_DATABASE:-appdb}"
    log_info "   Data: /var/lib/mysql"
    log_info "   Logs: /var/log/mysql"
    log_info "   Backup: /backup"

    if [[ "${DEPLOYMENT_ENVIRONMENT}" == "ECS" ]]; then
        log_info "   ECS optimizations: enabled"
    fi

    if [[ "${BACKUP_ENABLED:-true}" == "true" ]]; then
        if [[ -f "/var/run/mysqld/backup-daemon.pid" ]]; then
            local backup_pid
            backup_pid=$(cat /var/run/mysqld/backup-daemon.pid 2>/dev/null || echo "")
            if [[ -n "$backup_pid" ]] && kill -0 "$backup_pid" 2>/dev/null; then
                log_info "   Backup daemon: running (PID: $backup_pid)"
            else
                log_info "   Backup daemon: failed to start"
            fi
        else
            log_info "   Backup daemon: not started"
        fi
    else
        log_info "   Backup daemon: disabled"
    fi

    log_info ""
}

# ========================================
# MAIN ENTRYPOINT LOGIC
# ========================================

main() {
    log_info "MariaDB Container Starting..."
    log_info "   Stack Version: ${STACK_VERSION:-11.4}"

    # Step 1: Detect where we're running
    detect_deployment_environment

    # Step 1.5: Configure ECS-specific environment if needed
    configure_ecs_environment

    # Step 2: Get credentials (AWS or env vars)
    if ! manage_mariadb_credentials; then
        log_error "No MariaDB password available!"
        exit 1
    fi

    # Step 3: Check MariaDB prerequisites
    if ! check_mariadb_prerequisites; then
        log_error "MariaDB prerequisites check failed!"
        exit 1
    fi

    # Step 4: Setup directories and permissions
    setup_directories_and_permissions

    # Step 5: Generate configuration
    generate_mariadb_config

    # Step 6: Print deployment summary
    print_deployment_summary

    # Step 7: Start backup daemon in background after MariaDB starts
    if [[ "${BACKUP_ENABLED:-true}" == "true" ]]; then
        {
            log_info "Will start backup daemon after MariaDB is ready..."
            sleep 10

            local attempts=0
            local max_attempts=30
            while [[ $attempts -lt $max_attempts ]]; do
                if mariadb-admin ping -h localhost --silent 2>/dev/null; then
                    log_success "MariaDB ready, starting backup daemon..."
                    start_backup_daemon
                    break
                fi

                ((attempts++))
                if [[ $attempts -eq $max_attempts ]]; then
                    log_warning "MariaDB not ready after ${max_attempts} attempts"
                    break
                fi
                sleep 2
            done
        } &
    fi

    log_success "MariaDB ready!"

    # Step 8: Call the original MariaDB entrypoint
    log_info "Executing original MariaDB entrypoint..."
    exec /usr/local/bin/docker-entrypoint-original.sh mariadbd
}

# Execute main function
main "$@"
