# Centralized Backup & Recovery Server

## Project Overview

The Centralized Backup & Recovery Server is a Linux-based project designed to protect important files by creating backups and recovering lost or accidentally deleted data.

The system provides both a **terminal-based menu** and a **web dashboard called BackupHub**, making backup operations simple and easy to manage.

## Problem Statement

Important files can be accidentally deleted, lost, or damaged. Manually creating backups takes time and may lead to mistakes.

Our project provides an automated backup and recovery system to help protect important data.

## Key Features

- **Full Backup:** Creates a complete backup of selected files.
- **Incremental Backup:** Backs up changes using GNU tar snapshot tracking.
- **Backup History:** Displays previously created backups.
- **Verify Backup:** Uses SHA-256 checksums to detect changes or corruption in backup archives.
- **Restore Files:** Recovers files from a full backup into a separate folder.
- **Activity Logs:** Records backup and recovery operations.
- **Automatic Scheduling:** Uses cron to schedule daily backups.
- **Web Dashboard:** Provides a user-friendly interface for backup operations.

## Technologies Used

| Technology | Purpose |
|---|---|
| Ubuntu Linux (WSL) | Operating environment |
| Bash Scripting | Automates backup and recovery |
| GNU tar | Creates backup archives |
| SHA-256 | Checks backup integrity |
| Cron | Schedules automatic backups |
| Socat | Connects the local web interface to the Bash handler |
| HTML | Website structure |
| CSS | Website styling |
| JavaScript | Website interactions |

## Project Structure

```text
backup-recovery-server/
├── dashboard/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── dashboard_scripts/
│   ├── launch_dashboard.sh
│   └── http_handler.sh
├── scripts/
│   ├── backup_manager.sh
│   ├── full_backup.sh
│   ├── incremental_backup.sh
│   └── http_handler.sh
├── source_data/
│   ├── HR/
│   │   └── employees.txt
│   ├── Finance/
│   │   └── transactions.txt
│   └── IT/
│       └── servers.txt
└── .gitignore
```

The application creates additional folders for backups, logs, and restored files during use. These generated files are excluded from GitHub.

## How to Run the Project

### 1. Clone the Repository

```bash
git clone https://github.com/Manyata2005/centralized-backup-recovery-server.git
cd centralized-backup-recovery-server
```

### 2. Install Required Tools

Run on Ubuntu:

```bash
sudo apt update
sudo apt install tar coreutils socat cron -y
```

### 3. Run the Terminal Menu

```bash
bash scripts/backup_manager.sh
```

### 4. Start the Web Dashboard

```bash
bash dashboard_scripts/launch_dashboard.sh
```

Open the complete local URL displayed in the terminal in your browser.

The dashboard normally uses port **8765**. The launcher may provide an access token as part of the URL.

### 5. Use the Dashboard

The dashboard allows users to create backups, view backup history, verify backup integrity, restore files, view logs, and configure scheduled backups.

**Note:** This is a locally hosted application, not a publicly hosted website. Scheduled backups require the Linux environment and cron service to be running at the scheduled time.

## How the System Works

1. The user selects an operation through the terminal menu or web dashboard.
2. Bash scripts execute the corresponding Linux commands.
3. GNU tar creates full or incremental backup archives.
4. SHA-256 checksums help verify backup integrity.
5. Backup archives are stored in the backup directory.
6. Files can be recovered into a separate restore directory.
7. Logs record operations, and cron can schedule backups.

## Testing

The project has been tested for:

- Full backup creation
- Incremental backup creation
- Backup integrity verification
- File restoration
- Activity log display
- Invalid terminal menu input handling
- Daily backup schedule configuration

## Future Improvements

- Cloud backup integration
- Email notifications for backup failures
- User authentication and access management
- Additional restore options
- Remote backup storage

## Conclusion

The Centralized Backup & Recovery Server provides a simple way to create, manage, verify, and restore backups using Linux.

It demonstrates practical applications of Linux administration, Bash scripting, file management, and automation.
