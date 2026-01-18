@echo off
cd /d "%~dp0"
echo Deploying Firestore Rules...
call firebase deploy --only firestore:rules
if %errorlevel% neq 0 (
    echo Deployment failed. Please ensure Firebase CLI is installed and you are logged in.
) else (
    echo Deployment successful!
)
pause