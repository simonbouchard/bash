#!/bin/bash

################################################################################
# File Quarantine Script
#
# Description: Recursively scans directories for specified file extensions,
#              quarantines them, and deletes old quarantined files after X days.
#              Optionally sends HTML email reports.
#
# Usage: ./file-quarantine.sh [--dry-run]
#
# By: Simon Bouchard <https://github.com/simonbouchard>
################################################################################

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

# Default configuration values
SCAN_DIRS="/path/to/scan"
QUARANTINE_ROOT="/var/quarantine"
FILE_EXTENSIONS="sql:bak:log:tmp:old"
RETENTION_DAYS=30
MIN_FILE_AGE_MINUTES=60
TRUNCATE_LOGS=false
TRUNCATE_SIZE="5MB"
EXCLUDE_PATTERNS="*/proc/*:*/sys/*:*/dev/*:*/tmp/*:*/.git/*:*/node_modules/*"
ENABLE_EMAIL=false
EMAIL_TO="admin@example.com"
EMAIL_FROM="quarantine@$(hostname)"
EMAIL_SUBJECT="File Quarantine Report - $(date +%Y-%m-%d)"
SMTP_SERVER=""
SMTP_USER=""
SMTP_PASS=""
SMTP_USE_TLS="true"

# ============================================================================
# SCRIPT INTERNALS (DO NOT MODIFY BELOW UNLESS YOU KNOW WHAT YOU'RE DOING)
# ============================================================================

# Script metadata
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RUN_DATE=$(date +%Y-%m-%d_%H-%M-%S)
DRY_RUN=false

# Counters
COUNT_QUARANTINED=0
COUNT_DELETED=0
COUNT_TRUNCATED=0
TOTAL_SIZE_QUARANTINED=0
TOTAL_SIZE_DELETED=0
TOTAL_SIZE_FREED=0

# Arrays to store file information for email report
declare -a QUARANTINED_FILES
declare -a DELETED_FILES

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

# Print colored messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Convert bytes to human-readable format
human_readable_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    fi
}

# Convert size string to bytes
size_to_bytes() {
    local size_str="$1"
    local num=$(echo "$size_str" | sed 's/[^0-9.]*//g')
    local unit=$(echo "$size_str" | sed 's/[0-9.]*//g' | tr '[:lower:]' '[:upper:]')

    if [ -z "$num" ]; then
        echo 0
        return 1
    fi

    case "$unit" in
        B)
            echo "${num%.*}"
            ;;
        KB|K)
            echo "$(awk "BEGIN {printf \"%.0f\", $num * 1024}")"
            ;;
        MB|M)
            echo "$(awk "BEGIN {printf \"%.0f\", $num * 1048576}")"
            ;;
        GB|G)
            echo "$(awk "BEGIN {printf \"%.0f\", $num * 1073741824}")"
            ;;
        *)
            log_error "Invalid size unit: $unit. Use B, KB, MB, or GB."
            echo 0
            return 1
            ;;
    esac
}

# Build find command with exclusions
build_find_command() {
    local scan_dir="$1"
    local find_cmd="find \"$scan_dir\" -type f"

    # Add exclude patterns
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [ -n "$pattern" ]; then
            find_cmd+=" ! -path \"$pattern\""
        fi
    done

    # Exclude .log files from quarantine if TRUNCATE_LOGS is enabled
    if [ "$TRUNCATE_LOGS" = true ]; then
        find_cmd+=" ! -iname \"*.log\""
    fi

    # Add file age filter (files older than MIN_FILE_AGE_MINUTES)
    find_cmd+=" -mmin +${MIN_FILE_AGE_MINUTES}"

    # Add extension filters
    find_cmd+=" \\("
    local first=true
    for ext in "${FILE_EXTENSIONS[@]}"; do
        if [ "$first" = true ]; then
            find_cmd+=" -iname \"*.${ext}\""
            first=false
        else
            find_cmd+=" -o -iname \"*.${ext}\""
        fi
    done
    find_cmd+=" \\)"

    echo "$find_cmd"
}

# Truncate a log file
truncate_log_file() {
    local file_path="$1"
    local file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    local truncate_bytes=$(size_to_bytes "$TRUNCATE_SIZE")

    # Check if file is larger than the truncate size
    if [ "$file_size" -le "$truncate_bytes" ]; then
        return 0
    fi

    local space_freed=$((file_size - truncate_bytes))

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would truncate: $file_path ($(human_readable_size $file_size) -> $(human_readable_size $truncate_bytes), freeing $(human_readable_size $space_freed))"
        COUNT_TRUNCATED=$((COUNT_TRUNCATED + 1))
        TOTAL_SIZE_FREED=$((TOTAL_SIZE_FREED + space_freed))
        return 0
    fi

    # Truncate the file
    if truncate -s "$truncate_bytes" "$file_path" 2>/dev/null; then
        log_success "Truncated: $file_path (was $(human_readable_size $file_size), freed $(human_readable_size $space_freed))"
        COUNT_TRUNCATED=$((COUNT_TRUNCATED + 1))
        TOTAL_SIZE_FREED=$((TOTAL_SIZE_FREED + space_freed))
        return 0
    else
        log_error "Failed to truncate: $file_path"
        return 1
    fi
}

# Quarantine a file
quarantine_file() {
    local file_path="$1"
    local file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

    # Determine quarantine destination preserving directory structure
    local relative_path="${file_path#/}"
    local quarantine_dest="${QUARANTINE_ROOT}/${relative_path}"
    local quarantine_dir=$(dirname "$quarantine_dest")

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would quarantine: $file_path -> $quarantine_dest"
        QUARANTINED_FILES+=("${file_path}|${file_size}|DRY-RUN")
        COUNT_QUARANTINED=$((COUNT_QUARANTINED + 1))
        TOTAL_SIZE_QUARANTINED=$((TOTAL_SIZE_QUARANTINED + file_size))
        return 0
    fi

    # Create quarantine directory if it doesn't exist
    if ! mkdir -p "$quarantine_dir" 2>/dev/null; then
        log_error "Failed to create quarantine directory: $quarantine_dir"
        return 1
    fi

    # Move the file
    if mv "$file_path" "$quarantine_dest" 2>/dev/null; then
        log_success "Quarantined: $file_path"
        QUARANTINED_FILES+=("${file_path}|${file_size}|$(date +%Y-%m-%d\ %H:%M:%S)")
        COUNT_QUARANTINED=$((COUNT_QUARANTINED + 1))
        TOTAL_SIZE_QUARANTINED=$((TOTAL_SIZE_QUARANTINED + file_size))

        # Set permissions to read-only
        chmod 440 "$quarantine_dest" 2>/dev/null

        return 0
    else
        log_error "Failed to quarantine: $file_path"
        return 1
    fi
}

# Delete old quarantined files
cleanup_old_files() {
    log_info "Checking for quarantined files older than ${RETENTION_DAYS} days..."

    if [ ! -d "$QUARANTINE_ROOT" ]; then
        log_warning "Quarantine directory does not exist: $QUARANTINE_ROOT"
        return 0
    fi

    # Find files older than RETENTION_DAYS
    while IFS= read -r -d '' file; do
        local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would delete: $file"
            DELETED_FILES+=("${file}|${file_size}|DRY-RUN")
            COUNT_DELETED=$((COUNT_DELETED + 1))
            TOTAL_SIZE_DELETED=$((TOTAL_SIZE_DELETED + file_size))
        else
            if rm -f "$file" 2>/dev/null; then
                log_success "Deleted old file: $file"
                DELETED_FILES+=("${file}|${file_size}|$(date +%Y-%m-%d\ %H:%M:%S)")
                COUNT_DELETED=$((COUNT_DELETED + 1))
                TOTAL_SIZE_DELETED=$((TOTAL_SIZE_DELETED + file_size))
            else
                log_error "Failed to delete: $file"
            fi
        fi
    done < <(find "$QUARANTINE_ROOT" -type f -mtime +${RETENTION_DAYS} -print0 2>/dev/null)

    # Clean up empty directories in quarantine
    if [ "$DRY_RUN" = false ] && [ "$COUNT_DELETED" -gt 0 ]; then
        find "$QUARANTINE_ROOT" -type d -empty -delete 2>/dev/null
    fi
}

# Generate HTML email report
generate_html_report() {
    local html_file="/tmp/quarantine_report_${RUN_DATE}.html"

    cat > "$html_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #4CAF50;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            border-bottom: 2px solid #ddd;
            padding-bottom: 5px;
        }
        .summary {
            background-color: #e8f5e9;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            border-left: 4px solid #4CAF50;
        }
        .summary-item {
            margin: 8px 0;
            font-size: 16px;
        }
        .summary-label {
            font-weight: bold;
            color: #2e7d32;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th {
            background-color: #4CAF50;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: bold;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .no-files {
            color: #777;
            font-style: italic;
            padding: 20px;
            text-align: center;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #ddd;
            color: #777;
            font-size: 12px;
            text-align: center;
        }
        .dry-run {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .dry-run-badge {
            color: #856404;
            font-weight: bold;
            font-size: 18px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>File Quarantine Report</h1>

        <div class="summary">
EOF

    cat >> "$html_file" <<EOF
            <div class="summary-item"><span class="summary-label">Date:</span> $(date +"%Y-%m-%d %H:%M:%S")</div>
            <div class="summary-item"><span class="summary-label">Hostname:</span> $(hostname)</div>
            <div class="summary-item"><span class="summary-label">Scan Directories:</span> ${SCAN_DIRS[*]}</div>
            <div class="summary-item"><span class="summary-label">Quarantine Root:</span> $QUARANTINE_ROOT</div>
            <div class="summary-item"><span class="summary-label">Monitored Extensions:</span> ${FILE_EXTENSIONS[*]}</div>
            <div class="summary-item"><span class="summary-label">Retention Period:</span> $RETENTION_DAYS days</div>
        </div>
EOF

    if [ "$DRY_RUN" = true ]; then
        cat >> "$html_file" <<'EOF'
        <div class="dry-run">
            <span class="dry-run-badge">⚠ DRY-RUN MODE</span>
            <p>This was a simulation. No files were actually moved or deleted.</p>
        </div>
EOF
    fi

    cat >> "$html_file" <<EOF
        <h2>Summary</h2>
        <div class="summary">
            <div class="summary-item"><span class="summary-label">Files Quarantined:</span> $COUNT_QUARANTINED ($(human_readable_size $TOTAL_SIZE_QUARANTINED))</div>
            <div class="summary-item"><span class="summary-label">Files Deleted:</span> $COUNT_DELETED ($(human_readable_size $TOTAL_SIZE_DELETED))</div>
        </div>
EOF

    # Quarantined files table
    cat >> "$html_file" <<EOF
        <h2>Quarantined Files ($COUNT_QUARANTINED)</h2>
EOF

    if [ ${#QUARANTINED_FILES[@]} -eq 0 ]; then
        echo '<div class="no-files">No files were quarantined.</div>' >> "$html_file"
    else
        cat >> "$html_file" <<'EOF'
        <table>
            <thead>
                <tr>
                    <th>File Path</th>
                    <th>Size</th>
                    <th>Timestamp</th>
                </tr>
            </thead>
            <tbody>
EOF
        for file_info in "${QUARANTINED_FILES[@]}"; do
            IFS='|' read -r path size timestamp <<< "$file_info"
            local readable_size=$(human_readable_size "$size")
            echo "<tr><td>$path</td><td>$readable_size</td><td>$timestamp</td></tr>" >> "$html_file"
        done
        echo '</tbody></table>' >> "$html_file"
    fi

    # Deleted files table
    cat >> "$html_file" <<EOF
        <h2>Deleted Files ($COUNT_DELETED)</h2>
EOF

    if [ ${#DELETED_FILES[@]} -eq 0 ]; then
        echo '<div class="no-files">No files were deleted.</div>' >> "$html_file"
    else
        cat >> "$html_file" <<'EOF'
        <table>
            <thead>
                <tr>
                    <th>File Path</th>
                    <th>Size</th>
                    <th>Timestamp</th>
                </tr>
            </thead>
            <tbody>
EOF
        for file_info in "${DELETED_FILES[@]}"; do
            IFS='|' read -r path size timestamp <<< "$file_info"
            local readable_size=$(human_readable_size "$size")
            echo "<tr><td>$path</td><td>$readable_size</td><td>$timestamp</td></tr>" >> "$html_file"
        done
        echo '</tbody></table>' >> "$html_file"
    fi

    # Footer
    cat >> "$html_file" <<EOF
        <div class="footer">
            Generated by $SCRIPT_NAME on $(hostname) at $(date +"%Y-%m-%d %H:%M:%S")
        </div>
    </div>
</body>
</html>
EOF

    echo "$html_file"
}

# Send email report
send_email() {
    if [ "$ENABLE_EMAIL" != true ]; then
        return 0
    fi

    log_info "Generating email report..."
    local html_file=$(generate_html_report)

    if [ ! -f "$html_file" ]; then
        log_error "Failed to generate HTML report"
        return 1
    fi

    log_info "Sending email to $EMAIL_TO..."

    # Check if we should use SMTP or local mail
    if [ -n "$SMTP_SERVER" ]; then
        send_email_smtp "$html_file"
    else
        send_email_local "$html_file"
    fi

    local result=$?

    # Clean up temporary HTML file
    rm -f "$html_file"

    return $result
}

# Send email using local mail/sendmail
send_email_local() {
    local html_file="$1"

    # Check if mail command is available
    if ! command -v mail &> /dev/null && ! command -v sendmail &> /dev/null; then
        log_error "Neither 'mail' nor 'sendmail' command found. Please install mailutils or configure SMTP."
        return 1
    fi

    # Try to use mail command first
    if command -v mail &> /dev/null; then
        # Detect if this is GNU mail or BSD mail
        local mail_type
        if mail --version &> /dev/null 2>&1; then
            mail_type="gnu"
        else
            mail_type="bsd"
        fi

        if [ "$mail_type" = "gnu" ]; then
            # GNU mail supports -t flag to read headers from message
            (
                echo "To: $EMAIL_TO"
                echo "From: $EMAIL_FROM"
                echo "Subject: $EMAIL_SUBJECT"
                echo "Content-Type: text/html; charset=UTF-8"
                echo "MIME-Version: 1.0"
                echo ""
                cat "$html_file"
            ) | mail -t

            if [ $? -eq 0 ]; then
                log_success "Email sent successfully via GNU mail"
                return 0
            fi
        else
            # BSD mail with MIME headers - create temporary file with proper headers
            local temp_email="/tmp/quarantine_email_${RUN_DATE}.txt"
            {
                echo "From: $EMAIL_FROM"
                echo "To: $EMAIL_TO"
                echo "Subject: $EMAIL_SUBJECT"
                echo "Content-Type: text/html; charset=UTF-8"
                echo "MIME-Version: 1.0"
                echo ""
                cat "$html_file"
            } > "$temp_email"

            # Use sendmail format with BSD mail
            if sendmail -t < "$temp_email" 2>/dev/null; then
                log_success "Email sent successfully via sendmail"
                rm -f "$temp_email"
                return 0
            fi

            # Fallback to piping with mail command if sendmail fails
            if mail -s "$EMAIL_SUBJECT" "$EMAIL_TO" < "$html_file" 2>/dev/null; then
                log_success "Email sent successfully via BSD mail"
                rm -f "$temp_email"
                return 0
            fi

            rm -f "$temp_email"
        fi
    fi

    # Fallback to sendmail
    if command -v sendmail &> /dev/null; then
        (
            echo "To: $EMAIL_TO"
            echo "From: $EMAIL_FROM"
            echo "Subject: $EMAIL_SUBJECT"
            echo "Content-Type: text/html; charset=UTF-8"
            echo "MIME-Version: 1.0"
            echo ""
            cat "$html_file"
        ) | sendmail -t

        if [ $? -eq 0 ]; then
            log_success "Email sent successfully via sendmail"
            return 0
        fi
    fi

    log_error "Failed to send email via local mail system"
    return 1
}

# Send email using external SMTP (requires curl)
send_email_smtp() {
    local html_file="$1"

    if ! command -v curl &> /dev/null; then
        log_error "curl command not found. Required for SMTP email sending."
        return 1
    fi

    local email_message="/tmp/email_message_${RUN_DATE}.txt"

    # Create email message
    cat > "$email_message" <<EOF
From: $EMAIL_FROM
To: $EMAIL_TO
Subject: $EMAIL_SUBJECT
Content-Type: text/html; charset=UTF-8
MIME-Version: 1.0

$(cat "$html_file")
EOF

    # Build curl command
    local curl_cmd="curl -s --url \"smtp://${SMTP_SERVER}\""
    curl_cmd+=" --mail-from \"$EMAIL_FROM\""
    curl_cmd+=" --mail-rcpt \"$EMAIL_TO\""
    curl_cmd+=" --upload-file \"$email_message\""

    if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
        curl_cmd+=" --user \"${SMTP_USER}:${SMTP_PASS}\""
    fi

    if [ "$SMTP_USE_TLS" = true ]; then
        curl_cmd+=" --ssl-reqd"
    fi

    # Execute curl command
    if eval "$curl_cmd"; then
        log_success "Email sent successfully via SMTP"
        rm -f "$email_message"
        return 0
    else
        log_error "Failed to send email via SMTP"
        rm -f "$email_message"
        return 1
    fi
}

# Display usage information
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

File Quarantine Script - Recursively scans directories for specified file
extensions, quarantines them, and deletes old quarantined files. Optionally
truncates .log files to a specified size limit.

OPTIONS:
    --dry-run               Simulate the quarantine process without actually moving
                            or deleting any files
    --truncate-logs         Enable truncation of .log files in scan directories
    --truncate-size SIZE    Set the truncate size for log files (default: 5MB)
                            Examples: 1MB, 100KB, 1GB, 500B
    -h, --help              Display this help message

CONFIGURATION:
    Edit the configuration section at the top of this script to customize:
    - Directories to scan
    - Quarantine root directory
    - File extensions to monitor
    - Retention period for quarantined files
    - Log truncation settings (TRUNCATE_LOGS, TRUNCATE_SIZE)
    - Email notification settings
    - Exclude patterns

EXAMPLES:
    # Run in production mode
    $SCRIPT_NAME

    # Test what would happen without making changes
    $SCRIPT_NAME --dry-run

    # Truncate all .log files to 10MB
    $SCRIPT_NAME --truncate-logs --truncate-size 10MB

    # Run with both quarantine and log truncation
    $SCRIPT_NAME --truncate-logs --truncate-size 5MB

    # Add to crontab to run daily at 2 AM with log truncation
    0 2 * * * /path/to/$SCRIPT_NAME --truncate-logs --truncate-size 5MB

EOF
}

# Load configuration from .env file if it exists
load_config() {
    local script_dir=$(cd "$(dirname "$0")" && pwd)
    local env_file="${script_dir}/.env"

    if [ ! -f "$env_file" ]; then
        log_error "Configuration file not found: $env_file"
        log_error "Please create a .env file. See .env.example for reference."
        exit 1
    fi

    # Source the .env file, filtering out comments and empty lines
    while IFS='=' read -r key value; do
        # Skip empty lines and lines starting with #
        if [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Remove quotes if present
        value="${value%\"}"
        value="${value#\"}"

        # Skip if value is empty after processing
        [[ -z "$value" ]] && continue

        # Expand environment variables and command substitutions
        value=$(eval echo "$value")

        # Use declare to set variable dynamically
        declare -g "$key=$value"
    done < "$env_file"

    # Convert colon-separated strings to arrays
    IFS=':' read -ra SCAN_DIRS <<< "$SCAN_DIRS"
    IFS=':' read -ra FILE_EXTENSIONS <<< "$FILE_EXTENSIONS"
    IFS=':' read -ra EXCLUDE_PATTERNS <<< "$EXCLUDE_PATTERNS"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Load configuration from .env file
    load_config

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --truncate-logs)
                TRUNCATE_LOGS=true
                shift
                ;;
            --truncate-size)
                if [ -z "$2" ]; then
                    log_error "--truncate-size requires an argument (e.g., 5MB)"
                    usage
                    exit 1
                fi
                TRUNCATE_SIZE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Display header
    echo "======================================================================="
    echo "  File Quarantine Script"
    echo "  Run Date: $RUN_DATE"
    if [ "$DRY_RUN" = true ]; then
        echo "  Mode: DRY-RUN (simulation only)"
    fi
    if [ "$TRUNCATE_LOGS" = true ]; then
        echo "  Log Truncation: ENABLED (size limit: $TRUNCATE_SIZE)"
    fi
    echo "======================================================================="
    echo ""

    # Validate configuration
    if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
        log_error "No scan directories configured. Please edit SCAN_DIRS in the script."
        exit 1
    fi

    if [ ${#FILE_EXTENSIONS[@]} -eq 0 ]; then
        log_error "No file extensions configured. Please edit FILE_EXTENSIONS in the script."
        exit 1
    fi

    if [ -z "$QUARANTINE_ROOT" ]; then
        log_error "QUARANTINE_ROOT not configured. Please edit the script."
        exit 1
    fi

    # Validate scan directories exist
    for scan_dir in "${SCAN_DIRS[@]}"; do
        if [ ! -d "$scan_dir" ]; then
            log_warning "Scan directory does not exist: $scan_dir"
        fi
    done

    # Create quarantine root if it doesn't exist
    if [ "$DRY_RUN" = false ] && [ ! -d "$QUARANTINE_ROOT" ]; then
        if ! mkdir -p "$QUARANTINE_ROOT"; then
            log_error "Failed to create quarantine root: $QUARANTINE_ROOT"
            exit 1
        fi
        log_success "Created quarantine root: $QUARANTINE_ROOT"
    fi

    # Phase 1: Truncate log files (if enabled)
    if [ "$TRUNCATE_LOGS" = true ]; then
        log_info "Starting log file truncation..."
        echo ""

        for scan_dir in "${SCAN_DIRS[@]}"; do
            if [ ! -d "$scan_dir" ]; then
                continue
            fi

            log_info "Truncating logs in: $scan_dir"

            # Find and truncate .log files
            while IFS= read -r -d '' file; do
                truncate_log_file "$file"
            done < <(find "$scan_dir" -type f -iname "*.log" -print0 2>/dev/null)
        done

        echo ""
        log_info "Log truncation phase complete"
        echo ""
    fi

    # Phase 2: Scan and quarantine files
    log_info "Starting file scan and quarantine process..."
    echo ""

    for scan_dir in "${SCAN_DIRS[@]}"; do
        if [ ! -d "$scan_dir" ]; then
            continue
        fi

        log_info "Scanning: $scan_dir"

        # Build and execute find command
        local find_cmd=$(build_find_command "$scan_dir")

        while IFS= read -r -d '' file; do
            quarantine_file "$file"
        done < <(eval "$find_cmd -print0 2>/dev/null")
    done

    echo ""
    log_info "Quarantine phase complete: $COUNT_QUARANTINED files quarantined ($(human_readable_size $TOTAL_SIZE_QUARANTINED))"
    echo ""

    # Phase 3: Clean up old quarantined files
    log_info "Starting cleanup of old quarantined files..."
    echo ""

    cleanup_old_files

    echo ""
    log_info "Cleanup phase complete: $COUNT_DELETED files deleted ($(human_readable_size $TOTAL_SIZE_DELETED))"
    echo ""

    # Phase 4: Send email report
    send_email

    # Final summary
    echo "======================================================================="
    echo "  SUMMARY"
    echo "======================================================================="
    echo "  Files Quarantined: $COUNT_QUARANTINED ($(human_readable_size $TOTAL_SIZE_QUARANTINED))"
    echo "  Files Deleted:     $COUNT_DELETED ($(human_readable_size $TOTAL_SIZE_DELETED))"
    if [ "$TRUNCATE_LOGS" = true ]; then
        echo "  Files Truncated:   $COUNT_TRUNCATED (Space freed: $(human_readable_size $TOTAL_SIZE_FREED))"
    fi
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "  *** DRY-RUN MODE - No files were actually modified ***"
    fi
    echo "======================================================================="

    exit 0
}

# Run main function
main "$@"
