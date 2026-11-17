@Echo Off
ECHO Preparing the lab environment...

REM - Get current directory
SET SUBDIR=%~dp0

REM - Restart SQL Server Service to force closure of any open connections
NET STOP MSSQLLaunchpad
NET STOP SQLSERVERAGENT
NET STOP MSSQLSERVER
NET START MSSQLSERVER
NET START SQLSERVERAGENT
NET START MSSQLLaunchpad

REM - Run SQL Script to prepare the database environment
ECHO Preparing Databases...
SQLCMD -E -C -v SUBDIR="%SUBDIR%" -i %SUBDIR%SetupFiles\Setup.sql

DEL %SUBDIR%Audit\*.* /F /Q

:: tidy up %COMPUTERNAME%\SQL2
SQLCMD -E -C -v SUBDIR="%SUBDIR%" -i %SUBDIR%SetupFiles\Setup_sql2.sql -S %COMPUTERNAME%\SQL2

REM - rename .ps1.txt files to .ps1
FOR /R %SUBDIR%.. %%i IN (*.ps1.txt) DO @REN %%~fi %%~ni



