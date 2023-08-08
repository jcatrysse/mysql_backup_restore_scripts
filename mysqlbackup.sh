#!/usr/local/bin/bash

# original source Jan Catrysse 2023-08-07
STORE_FOLDER="$HOME/MySQL-Backups/backup"
DB_LOGIN="$HOME/MySQL-Backups/mysqldump_defaults"

# Default values
# Default values
TODAY=$(date +"%Y%m%d")
DRY_RUN=false
ALL_DATABASES=false
SEPARATE_DATABASES=false
KEEP_DAYS=0

function display_help() {
    echo "MySQL Backup Script"
    echo "Usage: $0 [OPTIONS] [DATABASE_NAME...]"
    echo "Options:"
    echo "  --all           Dump all databases into a single file."
    echo "  --separate      Dump each specified database into a separate file."
    echo "  --keep [SUFFIX] Specify how long to keep backups (e.g., 1d, 1w, 1m, 1y)."
    echo "  --dryrun        Display the backup and cleanup commands without actually executing them."
    echo "  --clean         Delete backups older than the specified retention period."
    echo "  --help          Display this help message."
    echo
    echo "Example:"
    echo "  $0 --all --keep 7d"
    echo "  $0 --separate redmine_test another_database"
    echo "  $0 --dryrun --all --separate"
    echo "  $0 --dryrun --all --clean"
    exit 0
}

function convert_to_days() {
    local period=$1
    local TIME_UNIT="${period: -1}"
    local TIME_VALUE="${period:0:${#period}-1}"
    case $TIME_UNIT in
        d) echo $TIME_VALUE;;
        w) echo $(($TIME_VALUE * 7));;
        m) echo $(($TIME_VALUE * 30));;
        y) echo $(($TIME_VALUE * 365));;
        *) echo 0;; # Default to 0 for invalid values
    esac
}

# Process command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --all) ALL_DATABASES=true;;
        --separate) SEPARATE_DATABASES=true;;
        --dryrun) DRY_RUN=true;;
        --clean) CLEAN=true;;
        --keep) shift; KEEP_DAYS=$(convert_to_days $1);;
        --help) display_help; exit 0;;
        *) DATABASES+=("$1");;  # Add to DATABASES array
    esac
    shift
done

# If no options provided, display help and exit
if [[ "$ALL_DATABASES" = false && "$SEPARATE_DATABASES" = false && -z "$KEEP" && "$DRY_RUN" = false && "$CLEAN" = false && ${#DATABASES[@]} -eq 0 ]]; then
    display_help
    exit 1
fi

# Function to perform the actual backup
function do_backup() {
    local DB_NAME=$1
    local FILE_SUFFIX=""
    local FILE_SUFFIX="[${KEEP_DAYS}]"
    
    if [ "$DB_NAME" == "--all-databases" ]; then
        BACKUP_PATH="$STORE_FOLDER/all/backup_all_$TODAY$FILE_SUFFIX.sql.gz"
    else
        BACKUP_PATH="$STORE_FOLDER/$DB_NAME/backup_${DB_NAME}_$TODAY$FILE_SUFFIX.sql.gz"
    fi
    
    local BACKUP_DIR=$(dirname "$BACKUP_PATH")
    if [ ! -d "$BACKUP_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "DRY RUN: mkdir -p $BACKUP_DIR"
        else
            mkdir -p "$BACKUP_DIR"
        fi
    fi
    
    DRY_RUN_MESSAGE="DRY RUN: /usr/local/bin/mysqldump --defaults-extra-file=$DB_LOGIN --set-gtid-purged=OFF --no-tablespaces --flush-logs --source-data=2 --single-transaction --lock-tables $DB_NAME | gzip -9 > $BACKUP_PATH"
    
    if [ "$DRY_RUN" = true ]; then
        echo "$DRY_RUN_MESSAGE"
    else
        eval "${DRY_RUN_MESSAGE#DRY RUN: }"
    fi
}

# Function to perform cleanup based on the retention period
function do_cleanup() {
    [ "$DRY_RUN" = true ] && echo "Running cleanup..."

    find "$STORE_FOLDER" -name "backup_*\[*\].sql.gz" -type f | while read -r FILE; do
        local FILENAME=$(basename "$FILE")
        local retention_days=${FILENAME#*[}
        retention_days=${retention_days%].sql.gz}

        if [[ $retention_days -eq 0 ]]; then
            # Skip deletion for files with 0 retention (i.e., infinity)
            continue
        fi

        local FILE_TIMESTAMP=$(stat -f "%m" "$FILE")
        local CURRENT_TIMESTAMP=$(date +%s)
        local TIMESTAMP_DIFF=$(($CURRENT_TIMESTAMP - $FILE_TIMESTAMP))
        local FILE_AGE_DAYS=$(echo $TIMESTAMP_DIFF | awk '{print int($1/86400)}')

        if [[ "$FILE_AGE_DAYS" -gt "$retention_days" ]]; then
            if [ "$DRY_RUN" = true ]; then
                echo "Dry run - Would delete: $FILE"
            else
                rm -f "$FILE"
                #echo "Deleted old backup: $FILE"
            fi
        fi
    done

    [ "$DRY_RUN" = true ] && echo "Dry run completed. No files deleted."
}

# Backup all databases into a single file
if [ "$ALL_DATABASES" = true ]; then
    do_backup "--all-databases"
fi

# Backup individual databases
if [ "$SEPARATE_DATABASES" = true ]; then
    # If no databases are specifically mentioned, backup all databases
    if [ ${#DATABASES[@]} -eq 0 ]; then
        DATABASES=($(/usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN -Bse "show databases" | grep -i -v "_schema" | grep -i -v "sys" | grep -i -v "mysql"))
    fi

    for DB in "${DATABASES[@]}"; do
        do_backup "$DB"
    done
fi

# Perform cleanup if the --clean option is passed
if [ "$CLEAN" = true ]; then
    do_cleanup
fi
