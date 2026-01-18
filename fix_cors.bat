@echo off
echo Checking for gsutil...
where gsutil
if %errorlevel% neq 0 (
    echo ---------------------------------------------------------------
    echo gsutil is NOT installed. 
    echo We cannot fix the server configuration automatically.
    echo We must rely on the "Isolated Browser Session" method.
    echo ---------------------------------------------------------------
) else (
    echo gsutil found. Attempting to set CORS configuration...
    call gsutil cors set cors.json gs://harmony-by-intent.firebasestorage.app
    echo ---------------------------------------------------------------
    echo CORS configuration command finished.
    echo If you saw "Application finished" or no errors, it worked!
    echo ---------------------------------------------------------------
)
pause
