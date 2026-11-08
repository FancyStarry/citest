# 采集 GitHub Actions Windows runner 的系统与硬件信息，输出 Markdown 报告
# 用法: pwsh ./probe-windows.ps1 -OutFile <路径>
param(
    [string]$OutFile = (Join-Path $env:TEMP 'probe-report.md')
)

$sb = New-Object System.Text.StringBuilder
function W  { param([string]$t = '') [void]$sb.AppendLine($t) }
function H  { param([string]$t) W ''; W "### $t"; W '' }
function KV { param([string]$k, $v) if ([string]::IsNullOrEmpty([string]$v)) { $v = 'unknown' }; W "| $k | $v |" }
function Block {
    param([string]$Code)
    W '```'
    try {
        $out = & ([scriptblock]::Create($Code)) 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($out)) { W '(无输出)' } else { W $out.TrimEnd() }
    } catch { W "(执行失败: $($_.Exception.Message))" }
    W '```'
    W ''
}

W '# Windows Runner 硬件与环境探测报告'
W ''
W '| 项目 | 值 |'
W '|---|---|'
KV 'Runner 名称' $env:RUNNER_NAME
KV 'Runner OS'   $env:RUNNER_OS
KV 'Runner 架构' $env:RUNNER_ARCH
KV '镜像 OS'     $env:ImageOS
KV '镜像版本'    $env:ImageVersion
KV 'Job'         $env:GITHUB_JOB
KV '采集时间(UTC)' (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')

H '1. 操作系统'
Block '[System.Environment]::OSVersion.VersionString; "64 位进程: $([Environment]::Is64BitProcess)"; "CPU 架构: $env:PROCESSOR_ARCHITECTURE"'
Block 'Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,InstallDate,LastBootUpTime | Format-List'
Block 'systeminfo'

H '2. 硬件型号（虚拟机标识）'
Block 'Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory,NumberOfProcessors,NumberOfLogicalProcessors,SystemType | Format-List'
Block 'Get-CimInstance Win32_BIOS | Select-Object Manufacturer,Name,Version,SerialNumber,ReleaseDate | Format-List'

H '3. CPU'
Block 'Get-CimInstance Win32_Processor | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,L2CacheSize,L3CacheSize,VirtualizationFirmwareEnabled,AddressWidth | Format-List'

H '4. 内存'
Block '$t = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory; "总内存: $t 字节 = {0:N1} GiB" -f ($t/1GB)'
Block 'Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel,DeviceLocator,@{n="CapacityGB";e={[math]::Round($_.Capacity/1GB,1)}},Speed,Manufacturer,PartNumber | Format-Table -AutoSize'

H '5. 磁盘'
Block 'Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystem,@{n="SizeGB";e={[math]::Round($_.Size/1GB,1)}},@{n="FreeGB";e={[math]::Round($_.SizeRemaining/1GB,1)}} | Format-Table -AutoSize'
Block 'Get-CimInstance Win32_DiskDrive | Select-Object Model,@{n="SizeGB";e={[math]::Round($_.Size/1GB,1)}},MediaType,InterfaceType,Partitions | Format-Table -AutoSize'
Block '"工作目录: $PWD"; "可用空间: {0:N1} GiB" -f ((Get-PSDrive C).Free/1GB)'

H '6. GPU / 显示'
Block 'Get-CimInstance Win32_VideoController | Select-Object Name,VideoProcessor,@{n="AdapterRAM_MB";e={[math]::Round($_.AdapterRAM/1MB,0)}},DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution | Format-List'

H '7. 网络'
Block 'Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object Name,InterfaceDescription,LinkSpeed,MacAddress | Format-Table -AutoSize'
Block 'Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias,IPAddress,PrefixLength | Format-Table -AutoSize'
Block '$ip = try { (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10) } catch { "(获取失败)" }; "公网出口 IP: $ip"'

H '8. 预装工具版本'
Block 'foreach ($c in @("dotnet","node","npm","python","git","docker","choco","pwsh","msbuild","cl")) { $p = Get-Command $c -ErrorAction SilentlyContinue; if ($p) { $v = try { (& $c --version 2>&1 | Select-Object -First 1) } catch { "(无法获取)" }; "{0,-8}: {1}" -f $c, $v } else { "{0,-8}: (未安装)" -f $c } }'
Block 'foreach ($c in @("go","java","rustc")) { $p = Get-Command $c -ErrorAction SilentlyContinue; if ($p) { $v = if ($c -eq "go") { (& go version) } elseif ($c -eq "java") { (& java -version 2>&1 | Select-Object -First 1) } else { (& rustc --version) }; "{0,-8}: {1}" -f $c, $v } else { "{0,-8}: (未安装)" -f $c } }'
Block '"Visual Studio 安装:"; if (Test-Path "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe") { & "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property displayName,installationVersion 2>&1 } else { "(未找到 vswhere)" }'

H '9. Actions 环境变量'
Block 'Get-ChildItem Env: | Where-Object { $_.Name -match "^(RUNNER_|GITHUB_|ImageOS|ImageVersion|ACTIONS_)" -and $_.Name -notmatch "(TOKEN|SECRET|KEY|PASSWORD)" } | Sort-Object Name | Format-Table -AutoSize Name,Value'

H '10. 性能粗测'
Block '$f = Join-Path $env:TEMP "perftest.bin"; $t = Measure-Command { $fs = [System.IO.File]::Create($f); $buf = New-Object byte[] (1MB); for ($i=0; $i -lt 512; $i++) { $fs.Write($buf,0,$buf.Length) }; $fs.Close() }; "磁盘写入 512MB: {0:N2} 秒 ({1:N0} MB/s)" -f $t.TotalSeconds, (512/$t.TotalSeconds)'
Block '$t = Measure-Command { Get-FileHash -Path (Join-Path $env:TEMP "perftest.bin") -Algorithm SHA256 | Out-Null }; "SHA256 512MB: {0:N2} 秒" -f $t.TotalSeconds'
Block 'Remove-Item (Join-Path $env:TEMP "perftest.bin") -ErrorAction SilentlyContinue; "(临时文件已清理)"'

W ''
W '---'
W "报告生成完毕: $OutFile"

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "报告已写入: $OutFile"
