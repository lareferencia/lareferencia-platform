# LA Referencia - Backup & Restore Guide

This guide describes how to use the automated backup system of the LA Referencia platform. The routine generates a full environment snapshot (databases, indices, and configurations) and creates an autonomous script to facilitate restoration.

## 1. Generating a Backup (Manual or Automatic)

Backup configuration and execution are managed through the platform's interactive Docker wizard.

### Step by Step:
1. Access the project's root directory:
   ```bash
   cd /path/to/lareferencia-platform
   ```
2. Start the interactive Docker wizard (the menu will open automatically):
   ```bash
   ./Docker/docker.sh
   ```
3. In the main menu, select the option **"💾 System Backup"**.
4. The wizard will prompt for:
   - **Backup Destination**: The path where the snapshots will be saved (default is `/var/backups/lareferencia-platform`). *Ensure the current user has write permissions for this directory.*
   - **Cron Schedule**: You can enable a daily backup that runs autonomously overnight.
   - **Immediate Execution**: The option to perform the first backup right away for validation.

### What is included in the Snapshot (`.tar.gz`)?
- Complete and clean database dumps from **PostgreSQL** (`lrharvester`) and **MariaDB** (`vufind`).
- Native volumes for the indexers (**Elasticsearch** and **Solr**), safely copied (services are paused prior to copying).
- The entire source code state (Git), excluding only build artifacts (`target/`) and the original database volumes (since they are exported as `.sql`).

> **Retention:** Each execution cleans up backups in the destination directory that are older than **7 days**.

---

## 2. Restoring a Backup

Every snapshot generated saves an autonomous script named `restore.sh` in its folder.

### Step by Step for Restoration:
1. Navigate to the specific backup directory you wish to restore:
   ```bash
   cd /var/backups/lareferencia-platform/YYYYMMDD_HHMM
   ```
   *Replace `YYYYMMDD_HHMM` with the desired date/time.*
   
2. Verify that both the `lareferencia_snapshot_YYYYMMDD_HHMM.tar.gz` file and the `restore.sh` script are present.

3. Execute the restoration script:
   ```bash
   bash restore.sh
   ```

### What does `restore.sh` do behind the scenes?
1. **Extraction**: Unpacks the repository, volumes, and database dumps from the `.tar.gz`.
2. **Initial Boot**: Initializes only the databases (`postgres` and `mariadb`).
3. **Import**: Waits for 15 seconds and imports the `.sql` files directly into the containers. If data already exists, it will be safely overwritten.
4. **Full Boot**: Starts all other infrastructure components (indexers, APIs, and frontend) which will consume the newly restored data.

> **Warning:** Executing the restoration will replace the current environment data associated with those containers.
