# File Quarantine Script

A comprehensive bash script that recursively scans directories for specified file extensions, quarantines them in a structured directory while preserving the original path, and automatically deletes old quarantined files after a configurable retention period. Optionally sends detailed HTML email reports.

## Features

- **Recursive Directory Scanning**: Scans multiple directories for specified file extensions
- **Structured Quarantine**: Preserves original directory structure in quarantine folder
- **Automatic Cleanup**: Deletes quarantined files older than X days
- **HTML Email Reports**: Sends detailed reports with file lists and statistics
- **Dry-Run Mode**: Test the script without making any changes
- **Exclude Patterns**: Skip specific directories (e.g., /proc, /sys, .git)
- **Minimum File Age**: Avoid quarantining actively used files
- **Color-Coded Output**: Easy-to-read console output with status indicators
- **SMTP Support**: Works with local mail or external SMTP servers

## Requirements

### Basic Requirements

- Bash 4.0 or higher
- Standard Unix utilities: `find`, `stat`, `awk`, `date`

### Email Requirements (Optional)

Choose one of the following:

**Option 1: Local Mail**

- `mail` or `sendmail` command (install `mailutils` or `postfix`)

**Option 2: External SMTP**

- `curl` command for SMTP support

## Installation

1. Download the script:

```bash
cd /opt/scripts
curl -O https://path-to-script/file-quarantine.sh
chmod +x file-quarantine.sh
```

2. Configure the script by editing the configuration section at the top:

```bash
nano file-quarantine.sh
```

## Configuration

Edit the configuration section at the top of the script:

```bash
# Directories to scan (can be multiple)
SCAN_DIRS=(
    "/var/www/html"
    "/home/users"
)

# Root quarantine directory
QUARANTINE_ROOT="/var/quarantine"

# File extensions to monitor (without the dot)
FILE_EXTENSIONS=(
    "sql"
    "bak"
    "log"
    "tmp"
    "old"
)

# Days to keep quarantined files before deletion
RETENTION_DAYS=30

# Minimum file age (in minutes) before quarantine
MIN_FILE_AGE_MINUTES=60

# Exclude patterns
EXCLUDE_PATTERNS=(
    "*/proc/*"
    "*/sys/*"
    "*/dev/*"
    "*/.git/*"
)

# Email Configuration
ENABLE_EMAIL=true
EMAIL_TO="admin@example.com"
EMAIL_FROM="quarantine@$(hostname)"
```

### SMTP Configuration (Optional)

For external SMTP servers (Gmail, Office365, etc.):

```bash
SMTP_SERVER="smtp.gmail.com:587"
SMTP_USER="your-email@gmail.com"
SMTP_PASS="your-app-password"
SMTP_USE_TLS="true"
```

## Usage

### Manual Execution

```bash
# Run in production mode
./file-quarantine.sh

# Test with dry-run (no files moved or deleted)
./file-quarantine.sh --dry-run

# Show help
./file-quarantine.sh --help
```

### Cron Setup

To run the script daily at 2:00 AM:

```bash
# Edit crontab
crontab -e

# Add this line
0 2 * * * /opt/scripts/file-quarantine.sh >> /var/log/quarantine.log 2>&1
```

### Common Cron Schedules

```bash
# Daily at 2:00 AM
0 2 * * * /opt/scripts/file-quarantine.sh

# Every 6 hours
0 */6 * * * /opt/scripts/file-quarantine.sh

# Every Sunday at 3:00 AM
0 3 * * 0 /opt/scripts/file-quarantine.sh

# First day of every month at 1:00 AM
0 1 1 * * /opt/scripts/file-quarantine.sh
```

## How It Works

### Phase 1: File Scanning and Quarantine

1. Scans all configured directories recursively
2. Finds files matching specified extensions
3. Filters files older than MIN_FILE_AGE_MINUTES
4. Excludes files matching EXCLUDE_PATTERNS
5. Moves matching files to quarantine while preserving directory structure
6. Sets quarantined files to read-only (440 permissions)

Example:

```
Original: /var/www/html/uploads/backup.sql
Quarantined: /var/quarantine/var/www/html/uploads/backup.sql
```

### Phase 2: Cleanup Old Files

1. Scans quarantine directory for files older than RETENTION_DAYS
2. Deletes old files
3. Removes empty directories

### Phase 3: Email Report

1. Generates HTML report with detailed file lists
2. Sends via local mail or SMTP
3. Includes statistics and timestamps

## Email Report Example

The HTML email includes:

- **Summary Section**
  - Date and hostname
  - Scan directories and quarantine root
  - Monitored extensions
  - Retention period

- **Statistics**
  - Number of files quarantined
  - Total size quarantined
  - Number of files deleted
  - Total size freed

- **Detailed Tables**
  - Quarantined files with paths, sizes, and timestamps
  - Deleted files with paths, sizes, and timestamps

## Quarantine Directory Structure

The script preserves the original directory structure:

```
/var/quarantine/
├── var/
│   └── www/
│       └── html/
│           ├── backup.sql
│           └── debug.log
└── home/
    └── user/
        └── data/
            └── old_export.bak
```

## Security Considerations

1. **Permissions**: Run as root or user with appropriate permissions
2. **Quarantine Location**: Store quarantine directory on a separate partition if possible
3. **Read-Only**: Quarantined files are set to 440 (read-only)
4. **SMTP Credentials**: Protect the script file if storing SMTP passwords
5. **Email Security**: Consider using app passwords instead of main account passwords

## Troubleshooting

### No Files Being Quarantined

Check:

- File extensions are configured correctly (without dots)
- Scan directories exist and are accessible
- Files are older than MIN_FILE_AGE_MINUTES
- Files are not in excluded patterns
- Run with `--dry-run` to see what would be quarantined

### Email Not Sending

Local mail:

```bash
# Check if mail command exists
which mail

# Install mailutils (Debian/Ubuntu)
apt-get install mailutils

# Install postfix (CentOS/RHEL)
yum install postfix
```

SMTP:

```bash
# Check if curl exists
which curl

# Test SMTP connection
curl -v smtp://smtp.gmail.com:587
```

### Permission Denied Errors

```bash
# Make script executable
chmod +x file-quarantine.sh

# Run as root if scanning system directories
sudo ./file-quarantine.sh --dry-run
```

## Best Practices

1. **Always test first**: Use `--dry-run` before running in production
2. **Start conservatively**: Begin with a longer MIN_FILE_AGE_MINUTES (e.g., 1440 = 24 hours)
3. **Monitor disk space**: Ensure quarantine partition has sufficient space
4. **Review email reports**: Check for unexpected files being quarantined
5. **Adjust retention**: Balance between recovery time and disk usage
6. **Exclude active directories**: Add application temp directories to EXCLUDE_PATTERNS
7. **Test email delivery**: Verify email reports are received and formatted correctly

## Examples

### Example 1: Web Server Security

Monitor web directories for potentially dangerous uploads:

```bash
SCAN_DIRS=(
    "/var/www/html/uploads"
    "/var/www/html/public"
)

FILE_EXTENSIONS=(
    "sql"
    "bak"
    "php.bak"
    "old"
    "backup"
)

MIN_FILE_AGE_MINUTES=30
RETENTION_DAYS=90
```

### Example 2: Log Management

Clean up old log files while keeping backups:

```bash
SCAN_DIRS=(
    "/var/log"
    "/opt/app/logs"
)

FILE_EXTENSIONS=(
    "log"
    "log.1"
    "log.old"
)

MIN_FILE_AGE_MINUTES=1440  # 1 day
RETENTION_DAYS=30
```

### Example 3: Development Environment

Remove old development artifacts:

```bash
SCAN_DIRS=(
    "/home/dev/projects"
)

FILE_EXTENSIONS=(
    "tmp"
    "bak"
    "swp"
    "swo"
)

EXCLUDE_PATTERNS=(
    "*/.git/*"
    "*/node_modules/*"
    "*/.cache/*"
)

MIN_FILE_AGE_MINUTES=10080  # 1 week
RETENTION_DAYS=14
```

## Logging

To maintain persistent logs:

```bash
# Add to crontab with log redirection
0 2 * * * /opt/scripts/file-quarantine.sh >> /var/log/quarantine.log 2>&1

# Rotate logs with logrotate
cat > /etc/logrotate.d/quarantine << 'EOF'
/var/log/quarantine.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
}
EOF
```

## Recovery

To restore a quarantined file:

```bash
# Find the file in quarantine
find /var/quarantine -name "filename.ext"

# Restore to original location
# The path in quarantine mirrors the original
cp /var/quarantine/original/path/to/file.ext /original/path/to/file.ext

# Or move it back
mv /var/quarantine/original/path/to/file.ext /original/path/to/file.ext
```

## License

This script is provided as-is without warranty. Use at your own risk.

## Support

For issues or questions:

1. Review the troubleshooting section
2. Run with `--dry-run` to test
3. Check script permissions and configuration
4. Verify all required commands are available

## Version History

- **v1.0** (2025-10-29): Initial release
  - Recursive directory scanning
  - Structured quarantine with path preservation
  - Automatic cleanup of old files
  - HTML email reports
  - Dry-run mode
  - Exclude patterns and file age filters
