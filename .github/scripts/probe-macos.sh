#!/usr/bin/env bash
# 采集 GitHub Actions macOS runner 的系统与硬件信息，输出 Markdown 报告
# 用法: bash probe-macos.sh [输出文件路径]
set -uo pipefail

OUT="${1:-/tmp/probe-report.md}"
: >"$OUT"

h()    { printf '\n### %s\n\n' "$1" >>"$OUT"; }
kv()   { printf '| %s | %s |\n' "$1" "$2" >>"$OUT"; }
block(){ printf '```\n' >>"$OUT"; bash -c "$1" >>"$OUT" 2>&1 || printf '(该命令返回非零，已忽略)\n' >>"$OUT"; printf '```\n\n' >>"$OUT"; }

printf '# macOS Runner 硬件与环境探测报告\n\n' >>"$OUT"
printf '| 项目 | 值 |\n|---|---|\n' >>"$OUT"
kv "Runner 名称" "${RUNNER_NAME:-unknown}"
kv "Runner OS" "${RUNNER_OS:-unknown}"
kv "Runner 架构" "${RUNNER_ARCH:-unknown}"
kv "镜像 OS" "${ImageOS:-unknown}"
kv "镜像版本" "${ImageVersion:-unknown}"
kv "Job" "${GITHUB_JOB:-unknown}"
kv "采集时间(UTC)" "$(date -u '+%Y-%m-%d %H:%M:%S')"

h "1. 系统版本"
block 'sw_vers'
block 'uname -a'
block 'uptime; printf "启动时间: "; sysctl -n kern.boottime 2>/dev/null'

h "2. 硬件型号"
block 'echo "hw.model = $(sysctl -n hw.model 2>/dev/null)"'
block 'system_profiler SPHardwareDataType 2>/dev/null'
block 'ioreg -l 2>/dev/null | grep -iE "\"product-name\"|\"board-id\"" | head -5'

h "3. CPU / 芯片"
block 'echo "芯片/CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"'
block 'echo "逻辑核(hw.ncpu)        : $(sysctl -n hw.ncpu 2>/dev/null)"; echo "物理核(hw.physicalcpu) : $(sysctl -n hw.physicalcpu 2>/dev/null)"; echo "性能核(perflevel0)     : $(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)"; echo "能效核(perflevel1)     : $(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)"'
block 'printf "arm64 支持: "; sysctl -n hw.optional.arm64 2>/dev/null || echo 0'
block 'echo "缓存: L1i=$(sysctl -n hw.l1icachesize 2>/dev/null) L1d=$(sysctl -n hw.l1dcachesize 2>/dev/null) L2=$(sysctl -n hw.l2cachesize 2>/dev/null) L3=$(sysctl -n hw.l3cachesize 2>/dev/null) 行大小=$(sysctl -n hw.cachelinesize 2>/dev/null)"'

h "4. 内存"
block 'b=$(sysctl -n hw.memsize 2>/dev/null); echo "总内存: $b 字节 = $((b/1024/1024/1024)) GiB"; echo "页大小: $(sysctl -n hw.pagesize 2>/dev/null)"'
block 'vm_stat 2>/dev/null | head -12'
block 'sysctl vm.swapusage 2>/dev/null'

h "5. 磁盘"
block 'df -h'
block 'diskutil list 2>/dev/null'
block 'diskutil info / 2>/dev/null | grep -E "Device Node|Volume Name|File System|Total Size|Free Space|Disk Size|Solid State"'
block 'echo "工作目录: $PWD"; du -sh . 2>/dev/null'

h "6. GPU / 显示"
block 'system_profiler SPDisplaysDataType 2>/dev/null'

h "7. 网络"
block 'ifconfig -a 2>/dev/null | grep -E "^[a-z0-9]+:|inet " | head -30'
block 'netstat -rn -f inet 2>/dev/null | head -10'
block 'printf "公网出口 IP: "; curl -s --max-time 10 https://api.ipify.org || echo "(获取失败)"; echo'

h "8. 预装工具版本"
block 'for c in xcodebuild swift clang python3 node npm yarn brew docker git jq; do printf "%-10s: " "$c"; if command -v "$c" >/dev/null 2>&1; then "$c" --version 2>&1 | head -1; else echo "(未安装)"; fi; done'
block 'printf "%-10s: " go; command -v go >/dev/null 2>&1 && go version || echo "(未安装)"; printf "%-10s: " java; command -v java >/dev/null 2>&1 && { java -version 2>&1 | head -1; } || echo "(未安装)"'
block 'xcodebuild -version 2>/dev/null; printf "Xcode 路径: "; xcode-select -p 2>/dev/null'
block 'echo "brew formula 数量: $(brew list --formula 2>/dev/null | wc -l | tr -d " ")"; echo "brew cask 数量: $(brew list --cask 2>/dev/null | wc -l | tr -d " ")"'

h "9. Actions 环境变量"
block 'env | grep -E "^(RUNNER_|GITHUB_|ImageOS|ImageVersion|ACTIONS_)" | grep -viE "(token|secret|key|password)" | sort'

h "10. 性能粗测"
block 'echo "sha256 1GB (3 次):"; for i in 1 2 3; do /usr/bin/time -p bash -c "head -c 1073741824 /dev/zero | shasum -a 256 > /dev/null" 2>&1 | grep real; done'
block 'echo "磁盘写入 512MB:"; /usr/bin/time -p dd if=/dev/zero of=/tmp/ddtest bs=1m count=512 2>&1 | grep -E "bytes|real"; rm -f /tmp/ddtest'

printf '\n---\n报告生成完毕: %s\n' "$OUT" >>"$OUT"
echo "报告已写入: $OUT"
