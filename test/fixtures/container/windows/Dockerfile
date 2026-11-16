# A command run in the build proves the engine starts a Windows container, which only a matching Windows version does.
FROM mcr.microsoft.com/windows/nanoserver:ltsc2025
RUN cmd /c ver
CMD ["cmd", "/c", "echo", "ok"]
