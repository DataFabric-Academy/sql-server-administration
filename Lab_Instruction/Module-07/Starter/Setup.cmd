@Echo Off
ECHO Preparing the lab environment...

REM - Get current directory
SET SUBDIR=%~dp0

REM - Restart SQL Server Service
NET STOP SQLSERVERAGENT
NET STOP MSSQLSERVER
NET STOP SQLAGENT$SQL2
NET STOP MSSQL$SQL2
NET START MSSQLSERVER
NET START MSSQL$SQL2
NET START SQLAGENT$SQL2

REM - Run SQL Script to prepare the database environment
ECHO Configuring databases...
REM - wait until the SQL2 instance accepts connections
set /a WAITTRIES=0
:wait_sql2
set /a WAITTRIES+=1
sqlcmd -S %COMPUTERNAME%\SQL2 -E -C -Q "SELECT 1" >nul 2>&1
if errorlevel 1 if %WAITTRIES% lss 10 goto wait_sql2

SQLCMD -S %COMPUTERNAME%\SQL2 -E -C -i %SUBDIR%SetupFiles\Setup2.sql
REM - wait until the default instance accepts connections
set /a WAITTRIES=0
:wait_default
set /a WAITTRIES+=1
sqlcmd -E -C -Q "SELECT 1" >nul 2>&1
if errorlevel 1 if %WAITTRIES% lss 10 goto wait_default

REM - Ensure the Backups folder exists (Setup.sql writes backups there)
IF NOT EXIST D:\Labfiles\Lab07\Backups MKDIR D:\Labfiles\Lab07\Backups

SQLCMD -E -C -v SUBDIR="%SUBDIR%" -i %SUBDIR%SetupFiles\Setup.sql

REM Sabotage AdventurWorks
ECHO Sabotaging databases...
NET STOP MSSQLSERVER
DEL D:\Labfiles\Lab07\Starter\SetupFiles\HumanResources.mdf /Q
COPY %SUBDIR%SetupFiles\InternetSales.mdf.txt %SUBDIR%SetupFiles\InternetSales.mdf /Y
NET START MSSQLSERVER
NET START SQLSERVERAGENT

PAUSE





