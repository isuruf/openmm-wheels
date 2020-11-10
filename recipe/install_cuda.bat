@echo ON

set "CUDA_VERSION=%1"

:: Get a recent driver -- currently linked one is from 2020.09.30
:: Update when necessary, especially after new releases.
set "CUDA_DRIVER_URL=https://us.download.nvidia.com/tesla/452.39/452.39-data-center-tesla-desktop-win10-64bit-international.exe"

:: We define a default subset of components to be installed from the network installer
:: for faster installation times. Full list of components in
:: https://docs.nvidia.com/cuda/archive/%CUDA_VERSION%/cuda-installation-guide-microsoft-windows/index.html
set "CUDA_COMPONENTS=nvcc_%CUDA_VERSION%"

if "%CUDA_VERSION%" == "9.2" goto cuda92
if "%CUDA_VERSION%" == "10.0" goto cuda100
if "%CUDA_VERSION%" == "10.1" goto cuda101
if "%CUDA_VERSION%" == "10.2" goto cuda102
if "%CUDA_VERSION%" == "11.0" goto cuda110
if "%CUDA_VERSION%" == "11.1" goto cuda111

echo CUDA '%CUDA_VERSION%' is not supported
exit /b 1

:: Define URLs per version
:cuda92
set "CUDA_NETWORK_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/9.2/Prod2/network_installers2/cuda_9.2.148_win10_network"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=2bf9ae67016867b68f361bf50d2b9e7b"
set "CUDA_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/9.2/Prod2/local_installers2/cuda_9.2.148_win10"
set "CUDA_INSTALLER_CHECKSUM=f6c170a7452098461070dbba3e6e58f1"
set "CUDA_PATCH_URL=https://developer.nvidia.com/compute/cuda/9.2/Prod2/patches/1/cuda_9.2.148.1_windows"
set "CUDA_PATCH_CHECKSUM=09e20653f1346d2461a9f8f1a7178ba2"
goto cuda_common


:cuda100
set "CUDA_NETWORK_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/10.0/Prod/network_installers/cuda_10.0.130_win10_network"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=3312deac9c939bd78d0e7555606c22fc"
set "CUDA_INSTALLER_URL=https://developer.nvidia.com/compute/cuda/10.0/Prod/local_installers/cuda_10.0.130_411.31_win10"
set "CUDA_INSTALLER_CHECKSUM=90fafdfe2167ac25432db95391ca954e"
goto cuda_common


:cuda101
set "CUDA_NETWORK_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.1/Prod/network_installers/cuda_10.1.243_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=fae0c958440511576691b825d4599e93"
set "CUDA_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.243_426.00_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=b54cf32683f93e787321dcc2e692ff69"
goto cuda_common


:cuda102
set "CUDA_NETWORK_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.2/Prod/network_installers/cuda_10.2.89_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=60e0f16845d731b690179606f385041e"
set "CUDA_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_441.22_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=d9f5b9f24c3d3fc456a3c789f9b43419"
set "CUDA_PATCH_URL=http://developer.download.nvidia.com/compute/cuda/10.2/Prod/patches/1/cuda_10.2.1_win10.exe"
set "CUDA_PATCH_CHECKSUM=9d751ae129963deb7202f1d85149c69d"
goto cuda_common


:cuda110
set "CUDA_NETWORK_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/11.0.3/network_installers/cuda_11.0.3_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=1b88bf7bb8e50207bbb53ed2033f93f3"
set "CUDA_INSTALLER_URL=http://developer.download.nvidia.com/compute/cuda/11.0.3/local_installers/cuda_11.0.3_451.82_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=80ae0fdbe04759123f3cab81f2aadabd"
goto cuda_common


:cuda111
set "CUDA_NETWORK_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.1.1/network_installers/cuda_11.1.1_win10_network.exe"
set "CUDA_NETWORK_INSTALLER_CHECKSUM=7e36e50ee486a84612adfd85500a9971"
set "CUDA_INSTALLER_URL=https://developer.download.nvidia.com/compute/cuda/11.1.1/local_installers/cuda_11.1.1_456.81_win10.exe"
set "CUDA_INSTALLER_CHECKSUM=a89dfad35fc1adf02a848a9c06cfff15"
goto cuda_common


:: The actual installation logic
:cuda_common

echo Downloading CUDA version %CUDA_VERSION% installer from %CUDA_NETWORK_INSTALLER_URL%
echo Expected MD5: %CUDA_NETWORK_INSTALLER_CHECKSUM%

:: Download installer
curl -k -L %CUDA_NETWORK_INSTALLER_URL% --output cuda_installer.exe
if errorlevel 1 (
    echo Problem downloading installer...
    exit /b 1
)

:: Check md5
openssl md5 cuda_installer.exe | findstr %CUDA_NETWORK_INSTALLER_CHECKSUM%
if errorlevel 1 (
    echo Checksum does not match!
    exit /b 1
)

:: Run installer
7z x cuda_installer.exe -ocuda_toolkit
if errorlevel 1 (
    echo Problem extracting CUDA toolkit installer...
    exit /b 1
)
del cuda_installer.exe
cd cuda_toolkit
mkdir cuda_tookit_install_logs
setup.exe -s %CUDA_COMPONENTS% -loglevel:6 -log:"cuda_tookit_install_logs"
if errorlevel 1 (
    echo Problem installing CUDA toolkit...
    mkdir "%CONDA_BLD_PATH%\logs"
    xcopy cuda_tookit_install_logs "%CONDA_BLD_PATH%\logs" /y
    exit /b 1
)
cd ..
rmdir /q /s cuda_toolkit

:: If patches are needed, download and apply
if not "%CUDA_PATCH_URL%"=="" (
    echo This version requires an additional patch
    curl -k -L %CUDA_PATCH_URL% --output cuda_patch.exe
    if errorlevel 1 (
        echo Problem downloading patch installer...
        exit /b 1
    )
    openssl md5 cuda_patch.exe | findstr %CUDA_PATCH_CHECKSUM%
    if errorlevel 1 (
        echo Checksum does not match!
        exit /b 1
    )
    cuda_patch.exe -s
    if errorlevel 1 (
        echo Problem running patch installer...
        exit /b 1
    )
    del cuda_patch.exe
)

:: Get drivers -- we don't want to install them, just a couple of DLLs
curl -k -L %CUDA_DRIVER_URL% --output cuda_drivers.exe
if errorlevel 1 (
    echo Problem downloading driver installer...
    exit /b 1
:: Extract and copy some DLLs (as per https://github.com/otabuzzman/cudacons)
7z x cuda_drivers.exe -ocuda_drivers
if errorlevel 1 (
    echo Problem extracting CUDA drivers...
    exit /b 1
)
del cuda_drivers.exe
xcopy cuda_drivers\Display.Driver\nvcuda64.dl_ "%CUDA_PATH%\bin\nvcuda.dll" /Y
if errorlevel 1 (
    echo Could not install nvcuda.dll
    exit /b 1
)
xcopy cuda_drivers\Display.Driver\nvfatbinaryloader64.dl_ "%CUDA_PATH%\bin\nvfatbinaryloader.dll" /Y
if errorlevel 1 (
    echo Could not install nvfatbinaryloader.dll
    exit /b 1
)
rmdir /q /s cuda_drivers

:: Add to PATH
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v%CUDA_VERSION%"

if "%CI%" == "azure" (
    echo "Exporting and adding $CUDA_PATH ('%CUDA_PATH%') to $PATH"
    echo ##vso[task.prependpath]%CUDA_PATH%\bin
    echo ##vso[task.setvariable variable=CUDA_PATH;]%CUDA_PATH%
    echo ##vso[task.setvariable variable=CUDA_HOME;]%CUDA_PATH%
)
