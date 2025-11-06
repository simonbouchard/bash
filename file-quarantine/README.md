# File Quarantine Script

A comprehensive bash script that recursively scans directories for specified file extensions, quarantines them in a structured directory while preserving the original path, automatically deletes old quarantined files after a configurable retention period, and optionally truncates log files to free up disk space. Optionally sends detailed HTML email reports.

## Features

- **Recursive Directory Scanning**: Scans multiple directories for specified file extensions
- **Structured Quarantine**: Preserves original directory structure in quarantine folder
- **Log File Truncation**: Optional truncation of .log files to a specified size limit with disk space tracking
- **Automatic Cleanup**: Deletes quarantined files older than X days
- **HTML Email Reports**: Sends detailed reports with file lists and statistics
- **Dry-Run Mode**: Test the script without making any changes
- **Exclude Patterns**: Skip specific directories (e.g., /proc, /sys, .git)
- **Minimum File Age**: Avoid quarantining actively used files
- **Color-Coded Output**: Easy-to-read console output with status indicators
- **SMTP Support**: Works with local mail or external SMTP servers (GNU and BSD compatible)
- **Space Freed Tracking**: Reports total disk space freed from truncated logs

## Requirements

### Basic Requirements

- Bash 4.0 or higher
- Standard Unix utilities: `find`, `stat`, `awk`, `date`, `truncate`

### Email Requirements (Optional)

Choose one of the following:

**Option 1: Local Mail (GNU or BSD)**

- `mail` or `sendmail` command (install `mailutils` on Linux or use system `mail` on BSD/macOS)

**Option 2: External SMTP**

- `curl` command for SMTP support

## Installation

1. Download the script:

```bash
cd /opt/scripts
git clone https://github.com/simonbouchard/file-quarantine.git
cd file-quarantine
chmod +x file-quarantine.sh
```

2. Create configuration file from example:

```bash
cp .env.example .env
nano .env
```

## Configuration

Configuration is managed via a `.env` file in the script directory. Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

### Basic Configuration

```bash
# Directories to scan (separated by colons for multiple directories)
SCAN_DIRS="/var/www/html:/home/users:/opt/app"

# Root quarantine directory
QUARANTINE_ROOT="/var/quarantine"

# File extensions to monitor (separated by colons, without dots)
FILE_EXTENSIONS="sql:bak:log:tmp:old:zip"

# Days to keep quarantined files before deletion
RETENTION_DAYS=30

# Minimum file age (in minutes) before quarantine
# This prevents quarantining actively used files
MIN_FILE_AGE_MINUTES=60
```

### Log Truncation Configuration

```bash
# Enable log file truncation (true/false)
TRUNCATE_LOGS=true

# Truncate size for log files (e.g., "5MB", "100KB", "1GB", "500B")
TRUNCATE_SIZE="5MB"
```

**Important**: When `TRUNCATE_LOGS=true`:

- `.log` files are **truncated** to the specified size and NOT quarantined
- Space freed is tracked and displayed in the summary
- Other configured extensions in log files will still be quarantined if needed

When `TRUNCATE_LOGS=false`:

- `.log` files are treated like any other extension
- They are quarantined normally if matching the FILE_EXTENSIONS list

### Exclude Patterns

```bash
# Patterns to exclude (separated by colons)
# Uses find's -path pattern matching
EXCLUDE_PATTERNS="*/proc/*:*/sys/*:*/dev/*:*/tmp/*:*/.git/*:*/node_modules/*"
```

### Email Configuration

```bash
# Enable email notifications (true/false)
ENABLE_EMAIL=true

# Recipient email address
EMAIL_TO="admin@example.com"

# Sender email address (supports environment variables)
EMAIL_FROM="quarantine@$(hostname)"

# Email subject (supports environment variables and command substitution)
EMAIL_SUBJECT="File Quarantine Report - $(date +%Y-%m-%d)"
```

### SMTP Configuration (Optional)

For external SMTP servers (Gmail, Office365, etc.):

```bash
# Leave empty to use local mail/sendmail
SMTP_SERVER="smtp.gmail.com:587"

# SMTP username
SMTP_USER="your-email@gmail.com"

# SMTP password
SMTP_PASS="your-app-password"

# Use TLS for SMTP (true/false)
SMTP_USE_TLS="true"
```

## Usage

### Manual Execution

```bash
# Run in production mode
./file-quarantine.sh

# Test with dry-run (no files moved or deleted)
./file-quarantine.sh --dry-run

# Truncate logs with custom size
./file-quarantine.sh --truncate-logs --truncate-size 10MB

# Show help
./file-quarantine.sh --help
```

### Command-Line Options

```
--dry-run               Simulate the quarantine process without actually moving
                        or deleting any files
--truncate-logs         Enable truncation of .log files in scan directories
--truncate-size SIZE    Set the truncate size for log files (default: 5MB)
                        Examples: 1MB, 100KB, 1GB, 500B
-h, --help              Display help message
```

### Cron Setup

To run the script daily at 2:00 AM:

```bash
# Edit crontab
crontab -e

# Add this line
0 2 * * * /opt/scripts/file-quarantine/file-quarantine.sh >> /var/log/quarantine.log 2>&1
```

### Common Cron Schedules

```bash
# Daily at 2:00 AM
0 2 * * * /opt/scripts/file-quarantine/file-quarantine.sh

# Daily at 2:00 AM with log truncation to 10MB
0 2 * * * /opt/scripts/file-quarantine/file-quarantine.sh --truncate-logs --truncate-size 10MB

# Every 6 hours
0 */6 * * * /opt/scripts/file-quarantine/file-quarantine.sh

# Every Sunday at 3:00 AM
0 3 * * 0 /opt/scripts/file-quarantine/file-quarantine.sh

# First day of every month at 1:00 AM
0 1 1 * * /opt/scripts/file-quarantine/file-quarantine.sh
```

## How It Works

### Phase 1: Log File Truncation (if enabled)

When `TRUNCATE_LOGS=true`:

1. Scans all configured directories for `.log` files
2. Truncates files larger than TRUNCATE_SIZE
3. Logs space freed per file
4. `.log` files are excluded from quarantine in Phase 2

### Phase 2: File Scanning and Quarantine

1. Scans all configured directories recursively
2. Finds files matching specified extensions
3. **Excludes `.log` files if TRUNCATE_LOGS=true**
4. Filters files older than MIN_FILE_AGE_MINUTES
5. Excludes files matching EXCLUDE_PATTERNS
6. Moves matching files to quarantine while preserving directory structure
7. Sets quarantined files to read-only (440 permissions)

Example:

```
Original: /var/www/html/uploads/backup.sql
Quarantined: /var/quarantine/var/www/html/uploads/backup.sql
```

### Phase 3: Cleanup Old Files

1. Scans quarantine directory for files older than RETENTION_DAYS
2. Deletes old files
3. Removes empty directories

### Phase 4: Email Report

1. Generates HTML report with detailed file lists
2. Sends via local mail (GNU or BSD) or external SMTP
3. Includes statistics, timestamps, and space tracking

## Email Report Example

The HTML email includes:

- **Summary Section**
  - Date and hostname
  - Scan directories and quarantine root
  - Monitored extensions
  - Retention period

- **Statistics**
  - Number of files quarantined and total size
  - Number of files deleted and space freed
  - Number of files truncated and space freed (if TRUNCATE_LOGS=true)

- **Detailed Tables**
  - Quarantined files with paths, sizes, and timestamps
  - Deleted files with paths, sizes, and timestamps

## Console Output Example

```
=======================================================================
  File Quarantine Script
  Run Date: 2025-11-05_14-30-45
  Mode: DRY-RUN (simulation only)
  Log Truncation: ENABLED (size limit: 5MB)
=======================================================================

[INFO] Starting log file truncation...

[INFO] Truncating logs in: /var/log
[SUCCESS] Truncated: /var/log/nginx/access.log (was 125.50MB, freed 120.50MB)
[SUCCESS] Truncated: /var/log/nginx/error.log (was 45.25MB, freed 40.25MB)

[INFO] Log truncation phase complete

[INFO] Starting file scan and quarantine process...

[INFO] Scanning: /home/www/webapps
[SUCCESS] [DRY-RUN] Would quarantine: /home/www/webapps/backup.sql -> /var/quarantine/home/www/webapps/backup.sql

[INFO] Quarantine phase complete: 5 files quarantined (125.50MB)

[INFO] Starting cleanup of old quarantined files...

[INFO] Cleanup phase complete: 2 files deleted (45.25MB)

[INFO] Generating email report...
[INFO] Sending email to admin@example.com...
[SUCCESS] Email sent successfully via BSD mail

=======================================================================
  SUMMARY
=======================================================================
  Files Quarantined: 5 (125.50MB)
  Files Deleted:     2 (45.25MB)
  Files Truncated:   2 (Space freed: 160.75MB)

  *** DRY-RUN MODE - No files were actually modified ***
=======================================================================
```

## Quarantine Directory Structure

The script preserves the original directory structure:

```
/var/quarantine/
├── var/
│   ├── www/
│   │   └── html/
│   │       ├── backup.sql
│   │       └── debug.log
│   └── log/
│       └── app/
│           └── error.log
└── home/
    └── user/
        └── data/
            └── old_export.bak
```

## Security Considerations

1. **Permissions**: Run as root or user with appropriate permissions
2. **Quarantine Location**: Store quarantine directory on a separate partition if possible
3. **Read-Only**: Quarantined files are set to 440 (read-only)
4. **Environment File**: Protect the `.env` file if storing SMTP credentials
   ```bash
   chmod 600 .env
   ```
5. **SMTP Credentials**: Use app passwords instead of main account passwords
6. **Email Security**: Verify TLS is enabled for external SMTP connections
7. **Log Files**: Keep logs of quarantine operations for audit purposes

## Troubleshooting

### Configuration File Not Found

```bash
# Create .env from example
cp .env.example .env

# Edit configuration
nano .env
```

### No Files Being Quarantined

Check:

- File extensions are configured correctly (without dots, separated by colons)
- Scan directories exist and are accessible
- Files are older than MIN_FILE_AGE_MINUTES
- Files are not in excluded patterns
- If TRUNCATE_LOGS=true, `.log` files won't be quarantined (they're truncated instead)
- Run with `--dry-run` to see what would be quarantined

### No Logs Being Truncated

Check:

- TRUNCATE_LOGS is set to `true` in `.env`
- TRUNCATE_SIZE is a valid format (e.g., "5MB", "100KB")
- Log files exist in scan directories
- Log files are larger than TRUNCATE_SIZE

### Email Not Sending

**Local Mail (Linux/BSD):**

```bash
# Check if mail/sendmail exists
which mail
which sendmail

# Install mailutils (Debian/Ubuntu)
apt-get install mailutils

# Install postfix (CentOS/RHEL)
yum install postfix

# Test mail command
echo "Test" | mail -s "Test Subject" admin@example.com
```

**External SMTP:**

```bash
# Check if curl exists
which curl

# Test SMTP connection
curl -v smtp://smtp.gmail.com:587

# Verify SMTP credentials in .env
nano .env
```

**macOS/BSD Mail Issues:**

The script automatically detects GNU vs BSD mail and uses appropriate flags. If you see "invalid option -- 't'" errors:

```bash
# Update to latest script version which includes BSD mail fix
git pull

# Or verify mail type
mail --version  # If no output, it's BSD mail
```

### Permission Denied Errors

```bash
# Make script executable
chmod +x file-quarantine.sh

# Make .env readable by the script user
chmod 600 .env

# Run as root if scanning system directories
sudo ./file-quarantine.sh --dry-run
```

### Truncated Log Files Have Wrong Size

Verify size format in `.env`:

```bash
# Valid formats:
TRUNCATE_SIZE="5MB"      # 5 megabytes
TRUNCATE_SIZE="100KB"    # 100 kilobytes
TRUNCATE_SIZE="1GB"      # 1 gigabyte
TRUNCATE_SIZE="500B"     # 500 bytes

# Invalid:
TRUNCATE_SIZE="5M"       # Missing 'B'
TRUNCATE_SIZE="5 MB"     # Has space
```

## Best Practices

1. **Test First**: Always use `--dry-run` before running in production
2. **Start Conservative**:
   - Use longer MIN_FILE_AGE_MINUTES initially (e.g., 1440 = 24 hours)
   - Set higher TRUNCATE_SIZE first, then gradually reduce
3. **Monitor Disk Space**: Ensure quarantine and log partitions have sufficient space
4. **Review Reports**: Check email reports for unexpected files
5. **Adjust Retention**: Balance recovery time vs disk usage
6. **Exclude Wisely**: Add active application temp directories to EXCLUDE_PATTERNS
7. **Test Email**: Verify HTML emails render correctly in your email client
8. **Backup Configuration**: Keep a copy of your `.env` file
9. **Log Rotation**: Set up logrotate for persistent script logs
10. **Schedule Strategically**: Run during low-traffic periods to minimize impact

## Examples

### Example 1: Web Server Security + Log Management

```bash
SCAN_DIRS="/var/www/html:/var/www/uploads:/var/log/nginx"
FILE_EXTENSIONS="sql:bak:log:tmp:old"
TRUNCATE_LOGS=true
TRUNCATE_SIZE="10MB"
MIN_FILE_AGE_MINUTES=60
RETENTION_DAYS=90
EXCLUDE_PATTERNS="*/node_modules/*:*/.git/*"
ENABLE_EMAIL=true
EMAIL_TO="admin@example.com"
```

### Example 2: Application Log Cleanup

```bash
SCAN_DIRS="/opt/app/logs:/var/log/app:/home/app/logs"
FILE_EXTENSIONS="log:log.1:log.2"
TRUNCATE_LOGS=true
TRUNCATE_SIZE="50MB"
MIN_FILE_AGE_MINUTES=1440    # 1 day
RETENTION_DAYS=30
ENABLE_EMAIL=false
```

### Example 3: Development Environment Cleanup

```bash
SCAN_DIRS="/home/dev/projects:/tmp/builds"
FILE_EXTENSIONS="tmp:bak:swp:swo:old"
TRUNCATE_LOGS=false
MIN_FILE_AGE_MINUTES=10080   # 1 week
RETENTION_DAYS=14
EXCLUDE_PATTERNS="*/.git/*:*/node_modules/*:*/.cache/*"
ENABLE_EMAIL=false
```

## Logging and Monitoring

To maintain persistent logs:

```bash
# Add to crontab with log redirection
0 2 * * * /opt/scripts/file-quarantine/file-quarantine.sh >> /var/log/quarantine.log 2>&1

# Rotate logs with logrotate
sudo tee /etc/logrotate.d/quarantine << 'EOF'
/var/log/quarantine.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF
```

View recent logs:

```bash
tail -f /var/log/quarantine.log
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

## Version History

- **v2.1** (2025-11-05): Log truncation and space tracking
  - Added log file truncation with configurable size limits
  - Exclude .log files from quarantine when TRUNCATE_LOGS=true
  - Track space freed from truncated logs
  - Display space freed in summary
  - Fixed BSD mail compatibility for HTML emails
  - Environment file configuration system

- **v2.0** (2025-10-29): Configuration file management
  - Moved all configuration to .env file
  - Support for multiple directories with colon-separated format
  - Improved email handling for GNU and BSD mail systems

- **v1.0** (2025-10-15): Initial release
  - Recursive directory scanning
  - Structured quarantine with path preservation
  - Automatic cleanup of old files
  - HTML email reports
  - Dry-run mode
  - Exclude patterns and file age filters

## License

This script is provided as-is without warranty. Use at your own risk.

## Support

For issues or questions:

1. Review the troubleshooting section
2. Run with `--dry-run` to test configuration
3. Check `.env` file syntax and values
4. Verify all required commands are available (`find`, `stat`, `truncate`, etc.)
5. Check script and configuration file permissions
