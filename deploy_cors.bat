@echo off
echo Setting CORS for bucket: harmony-by-intent.firebasestorage.app
echo You need to have gsutil installed (part of Google Cloud SDK).
echo If this command fails, you can also do this in the Google Cloud Console.
echo.
call gsutil cors set cors.json gs://harmony-by-intent.firebasestorage.app
echo.
pause