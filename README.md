# MySQL Backup and Restore Script

This script allows you to create backups of MySQL databases and restore them when needed. It simplifies the process of backing up and restoring individual databases or all databases at once.

## Features

- Backup individual databases or all databases in one go.
- Automatically select the latest backup when restoring individual databases.
- Check if the MySQL server is empty before restoring all databases to avoid accidental data loss.
- Display commands in a dry run mode without executing them for verification.

## Prerequisites

- The script assumes that you have `mysqldump` and `mysql` executables installed on your system.
- You need to specify the database login information in the `mysqldump_defaults` file.

## Usage
### Backup
Command:  
```
./mysqlbackup.sh [OPTIONS] [DATABASE_NAME...]
```

Options:  
```
--all           Dump all databases into a single file.
--separate      Dump each specified database into a separate file.
--keep [SUFFIX] Specify how long to keep backups (e.g., 1d, 1w, 1m, 1y).
--dryrun        Display the backup and cleanup commands without actually executing them.
--clean         Delete backups older than the specified retention period.
--help          Display this help message.
```

Example:  
```
./mysqlbackup.sh --all --separate --clean --keep 1w
./mysqlbackup.sh --dryrun --separate a_database another_database
```

### Restore

To restore databases, use the companion script `mysqlrestore.sh`. It provides similar options to restore individual databases or all databases from the latest backup.
The script should easily work for other backup files generated with `mysqldump`

Command:  
```
./mysqlrestore.sh [OPTIONS] [DATABASE_NAME...]
```

Options:  
```
--dryrun   Display the restore commands without actually executing them.
--y        Automatically confirm all prompts.
--all      Restore all databases from the latest backup.
--help     Display this help message.
```

Example:  
```
./mysqlrestore.sh --all --dryrun
./mysqlrestore.sh --dryrun a_database another_database
```

# Disclaimer

This script is experimental and provided as-is. Use it at your own risk. Make sure to test it in a safe environment before using it in production.

# License
## This project is licensed under the MIT License.

Feel free to contribute to the project and report any issues or bugs you encounter.
