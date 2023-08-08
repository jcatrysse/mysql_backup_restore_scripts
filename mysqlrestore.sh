#!/usr/local/bin/bash

# original source Jan Catrysse 2023-08-07
STORE_FOLDER="$HOME/MySQL-Backups/backup"
DB_LOGIN="$HOME/MySQL-Backup/mysqldump_defaults"
DRY_RUN=false
AUTO_CONFIRM=false
RESTORE_ALL=false

function display_help() {
    echo "MySQL Restore Script"
    echo "Usage: ./restore_script.sh [OPTIONS] DATABASE_NAME [DATABASE_NAME...]"
    echo "Options:"
    echo "  --dryrun   Display the restore commands without actually executing them."
    echo "  --y        Automatically confirm all prompts."
    echo "  --all      Restore all databases from the latest backup."
    echo "  --help     Display this help message."
    echo
    echo "Example:"
    echo "  ./restore_script.sh redmine_test another_database"
    echo "  ./restore_script.sh --all"
    echo "  ./restore_script.sh --dryrun --y redmine_test another_database"
}

# Process options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dryrun) DRY_RUN=true;;
        --y) AUTO_CONFIRM=true;;
        --all) RESTORE_ALL=true;;
        --help) display_help; exit 0;;
        *) break;; # Stop processing options on the first non-option argument
    esac
    shift
done

function get_latest_backup() {
    DB_NAME=$1
    INDIVIDUAL_BACKUP=$(ls $STORE_FOLDER/$DB_NAME/backup_*.sql.gz 2>/dev/null | sort | tail -n 1)
    ALL_BACKUP=$(ls $STORE_FOLDER/all/backup_*.sql.gz 2>/dev/null | sort | tail -n 1)

    if $RESTORE_ALL || [ -z "$INDIVIDUAL_BACKUP" ] || [ "$INDIVIDUAL_BACKUP" -nt "$ALL_BACKUP" ] || $AUTO_CONFIRM; then
        echo "$ALL_BACKUP"
    else
        read -p "$DB_NAME: Individual backup ($INDIVIDUAL_BACKUP) is older than all-databases backup ($ALL_BACKUP). Which one to use? (I/A): " choice
        case "$choice" in
            I|i) echo "$INDIVIDUAL_BACKUP";;
            A|a) echo "$ALL_BACKUP";;
            *) echo "Invalid choice. Exiting."; exit 1;;
        esac
    fi
}


function restore_database() {
    DB_NAME=$1
    BACKUP_FILE=$(get_latest_backup $DB_NAME)
    
    # Extract the username from $DB_LOGIN
    MYSQL_USERNAME=$(awk -F"=" '/user/ {print $2}' $DB_LOGIN)

    # Check if the backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Backup file $BACKUP_FILE does not exist! Restoration aborted."
        exit 1
    fi

    # Check if the database exists
    if ! /usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN -e "SHOW DATABASES LIKE '$DB_NAME'" | grep -q "$DB_NAME"; then
        echo "Error: Database $DB_NAME does not exist!"
        echo "Please create an empty database with the name '$DB_NAME' and grant the necessary privileges to the user in the $DB_LOGIN file."
        echo "Command to create database and to grant privileges:"
        echo "  CREATE DATABASE \`$DB_NAME\`; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$MYSQL_USERNAME'@'localhost';"
        exit 1
    fi

    # Check if the database is empty
    TABLE_COUNT=$(/usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN -Nse "SHOW TABLES FROM $DB_NAME" | wc -l)
    if [ "$TABLE_COUNT" -ne "0" ]; then
        echo "Error: Database $DB_NAME is not empty! Restoration aborted."
        exit 1
    fi

    # Distinguish between individual dump and all-databases dump
    if [[ $BACKUP_FILE == *"/all/"* ]]; then
        # Restore command for all-databases dump
        COMMAND="(echo 'SET foreign_key_checks = 0;' && gunzip < $BACKUP_FILE | sed -n '/^-- Current Database: \`$DB_NAME\`$/,/^-- Current Database:/p' && echo 'SET foreign_key_checks = 1;') | /usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN --one-database $DB_NAME"
    else
        # Restore command for individual dump
        COMMAND="gunzip < $BACKUP_FILE | /usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN $DB_NAME"
    fi

    if $DRY_RUN; then
        # Only display the command, do not execute
        echo "DRY RUN: $COMMAND"
    else
        echo "Restoring $DB_NAME from $BACKUP_FILE ..."
        #eval $COMMAND
        echo "Restoration of $DB_NAME completed."
        echo "After verifying the restoration, consider revoking the extra privileges with the command:"
        echo "  REVOKE ALL PRIVILEGES ON \`$DB_NAME\`.* FROM '$MYSQL_USERNAME'@'localhost';"
    fi
}

function restore_all_databases() {
    BACKUP_FILE=$(get_latest_backup "all") # Using "all" as a placeholder to signify all databases

    # Extract the username from $DB_LOGIN
    MYSQL_USERNAME=$(awk -F"=" '/user/ {print $2}' $DB_LOGIN)

    # Check if the backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Backup file $BACKUP_FILE does not exist! Restoration aborted."
        exit 1
    fi

    # Check if the MySQL server is empty (only default databases exist)
    DEFAULT_DATABASES=("information_schema" "mysql" "performance_schema" "sys")
    DATABASES_ON_SERVER=$(/usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN -Nse "SHOW DATABASES" | grep -v "${DEFAULT_DATABASES[*]}")

    if [ -z "$DATABASES_ON_SERVER" ]; then
        # MySQL server is empty, prompt for confirmation
        read -r -p "The MySQL server is currently empty. Do you want to proceed with the restoration? [y/N] " response
        if [[ "$response" =~ ^[yY]$ ]]; then
            # Proceed with restoration
            COMMAND="gunzip < $BACKUP_FILE | /usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN"

            if $DRY_RUN; then
                # Only display the command, do not execute
                echo "DRY RUN: $COMMAND"
            else
                echo "Restoring all databases from $BACKUP_FILE ..."
                eval $COMMAND
                echo "Restoration of all databases completed."
                # No need to display the privilege revoking commands as there are no databases to restore
            fi
        else
            # User chose not to proceed
            echo "Restoration aborted."
            exit 1
        fi
    else
        # Non-default databases exist, display a warning and ask for confirmation
        read -r -p "Warning: The MySQL server is not empty. Restoring all databases may overwrite existing data. Do you want to proceed? [y/N] " response
        if [[ "$response" =~ ^[yY]$ ]]; then
            # Proceed with restoration
            COMMAND="gunzip < $BACKUP_FILE | /usr/local/bin/mysql --defaults-extra-file=$DB_LOGIN"
    
            if $DRY_RUN; then
                # Only display the command, do not execute
                echo "DRY RUN: $COMMAND"
            else
                echo "Restoring all databases from $BACKUP_FILE ..."
                eval $COMMAND
                echo "Restoration of all databases completed."
                # No need to display the privilege revoking commands as there are no databases to restore
            fi
        else
            # User chose not to proceed
            echo "Restoration aborted."
            exit 1
        fi
    fi
}

# Check if at least one database is provided
if [ "$#" -eq 0 ] && [ "$RESTORE_ALL" = false ]; then
    echo "Error: No databases specified for restoration."
    display_help
    exit 1
fi

# If --all option is specified
if $RESTORE_ALL; then
    restore_all_databases
    exit 0
fi

# Loop through the databases provided and attempt restoration
for DB in "$@"; do
    restore_database $DB
done
