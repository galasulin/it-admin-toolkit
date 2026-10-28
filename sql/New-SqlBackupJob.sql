/* =====================================================================================
   New-SqlBackupJob.sql
   Daily full backup of one database as a SQL Server Agent job - no external scripts needed.
   -------------------------------------------------------------------------------------
   WHAT IT CREATES (re-runnable - existing objects with the same names are replaced):
     1. master.dbo.usp_BackupDatabase  - a generic procedure:
          BACKUP DATABASE ... WITH COMPRESSION, CHECKSUM, INIT, FORMAT
          -> RESTORE VERIFYONLY ... WITH CHECKSUM
          -> only after both succeeded: removes .bak files older than @KeepDays from that
             database's own sub-folder (xp_delete_file reads the backup header, so it deletes
             SQL Server backup files only)
        Backups go to  <BackupRoot>\<DatabaseName>\<DatabaseName>_FULL_yyyyMMdd_HHmmss.bak
     2. An Agent job "<DatabaseName> - Daily Full Backup" with a daily schedule.

   HOW TO USE
     Edit the SETTINGS block in batch 2 (database, folder, retention, time), then run the whole
     file in SSMS, with sqlcmd -i, or with ..\sql\Invoke-SqlFile.ps1.
     Run the job now:  EXEC msdb.dbo.sp_start_job N'<DatabaseName> - Daily Full Backup';

   REQUIREMENTS
     sysadmin (to create the procedure in master and the Agent job); SQL Server Agent running
     (not available on Express - use Backup-SqlDatabases.ps1 with Task Scheduler there).
     COMPRESSION needs an edition that supports it - remove it from the WITH list otherwise.

   SAFETY
     Writes backup files and DELETES older .bak files in <BackupRoot>\<DatabaseName>.
     A folder on the SQL Server itself is NOT disaster recovery: point @BackupRoot at a share on
     another machine (\\<FILE_SERVER>\<BACKUP_SHARE>) - the SQL Server SERVICE account needs write
     access to it - or copy the folder off the server.

   Author: Gal Asulin
   ===================================================================================== */

USE master;
GO
CREATE OR ALTER PROCEDURE dbo.usp_BackupDatabase
    @DatabaseName SYSNAME,
    @BackupRoot   NVARCHAR(400) = NULL,  -- NULL = the instance default backup folder
    @KeepDays     INT = 14,              -- 0 = keep everything
    @Verify       BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF DB_ID(@DatabaseName) IS NULL
    BEGIN
        RAISERROR(N'Database %s does not exist.', 16, 1, @DatabaseName);
        RETURN;
    END;

    IF @BackupRoot IS NULL
        SET @BackupRoot = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
    IF RIGHT(@BackupRoot, 1) = N'\' SET @BackupRoot = LEFT(@BackupRoot, LEN(@BackupRoot) - 1);

    DECLARE @folder NVARCHAR(600) = @BackupRoot + N'\' + @DatabaseName;
    EXEC master.dbo.xp_create_subdir @folder;

    DECLARE @stamp NVARCHAR(20) =
        REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(19), GETDATE(), 120), N'-', N''), N':', N''), N' ', N'_');
    DECLARE @file NVARCHAR(800) = @folder + N'\' + @DatabaseName + N'_FULL_' + @stamp + N'.bak';
    DECLARE @name NVARCHAR(200) = @DatabaseName + N' full backup ' + @stamp;

    BACKUP DATABASE @DatabaseName TO DISK = @file
        WITH COMPRESSION, CHECKSUM, INIT, FORMAT, STATS = 10, NAME = @name;

    IF @Verify = 1
        RESTORE VERIFYONLY FROM DISK = @file WITH CHECKSUM;

    -- Reached only when the backup (and the verify) succeeded.
    IF @KeepDays > 0
    BEGIN
        DECLARE @cutoff DATETIME = DATEADD(DAY, -@KeepDays, GETDATE());
        EXEC master.dbo.xp_delete_file 0, @folder, N'bak', @cutoff, 0;  -- 0 = this folder only
    END;

    PRINT N'Backup OK: ' + @file;
END;
GO

/* ------------------------------------------------------------------ batch 2: the Agent job */
USE msdb;
GO
-- ===================== SETTINGS =====================
DECLARE @DatabaseName SYSNAME       = N'<DATABASE_NAME>';
DECLARE @BackupRoot   NVARCHAR(400) = NULL;      -- e.g. N'\\<FILE_SERVER>\<BACKUP_SHARE>' ; NULL = instance default
DECLARE @KeepDays     INT           = 14;
DECLARE @StartTime    INT           = 20000;     -- HHMMSS as a number: 20000 = 02:00:00
-- ====================================================

DECLARE @jobName  SYSNAME = @DatabaseName + N' - Daily Full Backup';
DECLARE @schedule SYSNAME = @DatabaseName + N' - Daily Full Backup schedule';
DECLARE @command  NVARCHAR(MAX) =
      N'EXEC master.dbo.usp_BackupDatabase @DatabaseName = N''' + REPLACE(@DatabaseName, N'''', N'''''') + N''''
    + N', @BackupRoot = ' + CASE WHEN @BackupRoot IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(@BackupRoot, N'''', N'''''') + N'''' END
    + N', @KeepDays = ' + CAST(@KeepDays AS NVARCHAR(10)) + N';';

IF DB_ID(@DatabaseName) IS NULL
BEGIN
    RAISERROR(N'Set @DatabaseName in the SETTINGS block to an existing database first.', 16, 1);
    RETURN;
END;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName)
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName, @delete_unused_schedule = 1;

DECLARE @jobId BINARY(16);
EXEC msdb.dbo.sp_add_job @job_name = @jobName, @enabled = 1,
     @description = N'Daily compressed, checksummed and verified full backup + retention (New-SqlBackupJob.sql)',
     @job_id = @jobId OUTPUT;
EXEC msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Backup', @subsystem = N'TSQL',
     @database_name = N'master', @command = @command, @retry_attempts = 2, @retry_interval = 5;
EXEC msdb.dbo.sp_add_schedule @schedule_name = @schedule, @freq_type = 4, @freq_interval = 1,
     @active_start_time = @StartTime;
EXEC msdb.dbo.sp_attach_schedule @job_id = @jobId, @schedule_name = @schedule;
EXEC msdb.dbo.sp_add_jobserver @job_id = @jobId;

PRINT N'Job created: ' + @jobName + N'. Step command: ' + @command;
PRINT N'Run it now with: EXEC msdb.dbo.sp_start_job N''' + @jobName + N''';';
GO
