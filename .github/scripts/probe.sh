#!/usr/bin/env bash
# 收集 GitHub Actions runner（虚拟机/容器）的系统与硬件信息，输出 Markdown 报告
# 用法: bash probe.sh [输出文件路径]
set -uo pipefail

OUT="${1:-/tmp/probe-report.md}"
: >"$OUT"

h()   { printf '\n### %s\n\n' "$1" >>"$OUT"; }
kv()  { printf '| %s | %s |\n' "$1" "$2" >>"$OUT"; }
block(){ printf '```\n' >>"$OUT"; bash -c "$1" >>"$OUT" 2>&1 || printf '(该命令返回非零，已忽略)\n' >>"$OUT"; printf '```\n\n' >>"$OUT"; }

# ---------- 报告头 ----------
printf '# Runner 硬件与环境探测报告\n\n' >>"$OUT"
printf '| 项目 | 值 |\n|---|---|\n' >>"$OUT"
kv "Runner 名称" "${RUNNER_NAME:-unknown}"
kv "Runner OS" "${RUNNER_OS:-unknown}"
kv "Runner 架构" "${RUNNER_ARCH:-unknown}"
kv "镜像 OS" "${ImageOS:-unknown}"
kv "镜像版本" "${ImageVersion:-unknown}"
kv "Workflow" "${GITHUB_WORKFLOW:-unknown}"
kv "Job" "${GITHUB_JOB:-unknown}"
kv "采集时间(UTC)" "$(date -u '+%Y-%m-%d %H:%M:%S')"

# ---------- 1. 系统与内核 ----------
h "1. 系统与内核"
block 'cat /etc/os-release'
block 'uname -a'
block 'lsb_release -a 2>/dev/null || echo "(无 lsb_release)"'
block 'hostnamectl 2>/dev/null || echo "(无 hostnamectl / 非 systemd)"'
block 'uptime; echo; printf "启动时间: "; uptime -s 2>/dev/null || echo unknown'

# ---------- 2. CPU ----------
h "2. CPU"
block 'lscpu'
block 'echo "逻辑 CPU 数(nproc): $(nproc)"; echo "物理插槽: $(lscpu | awk -F: "/Socket/{gsub(/ /,\"\",\$2);print \$2}")"; echo "每核线程: $(lscpu | awk -F: "/Thread/{gsub(/ /,\"\",\$2);print \$2}")"'
block 'grep -m1 -E "model name|cpu model" /proc/cpuinfo'
block 'echo "虚拟化相关 flag:"; grep -oE "\b(vmx|svm|hypervisor|aes|avx2|avx512f)\b" /proc/cpuinfo | sort -u | tr "\n" " "; echo'
block 'echo "BogoMIPS / 缓存:"; grep -m1 -E "cache size" /proc/cpuinfo; lscpu | grep -iE "^(L1d|L1i|L2|L3)" || true'

# ---------- 3. 内存 ----------
h "3. 内存"
block 'free -h'
block 'grep -E "^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|HugePages_Total)" /proc/meminfo'
block 'echo "cgroup 内存限制:"; for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do [ -r "$f" ] && { printf "%s = " "$f"; cat "$f"; }; done; echo "(max = 不限)"'

# ---------- 4. 磁盘 ----------
h "4. 磁盘与文件系统"
block 'df -hT -x tmpfs -x devtmpfs'
block 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,ROTA 2>/dev/null || echo "(无 lsblk)"'
block 'echo "工作目录: $PWD"; du -sh . 2>/dev/null; echo "可用空间: $(df -h . | awk "NR==2{print \$4}")"'

# ---------- 5. 虚拟化与云厂商 ----------
h "5. 虚拟化平台 / 云厂商标识"
block 'systemd-detect-virt 2>/dev/null || echo "(无 systemd-detect-virt)"'
block 'for f in sys_vendor product_name product_version bios_vendor board_vendor; do printf "%-16s: " "$f"; cat "/sys/class/dmi/id/$f" 2>/dev/null || echo unknown; done'
block 'if command -v dmidecode >/dev/null && sudo -n true 2>/dev/null; then sudo dmidecode -t system -t bios 2>/dev/null | grep -E "Manufacturer|Product Name|Version|Vendor" | head -12; else echo "(dmidecode 不可用或需要密码)"; fi'
block 'echo "CPU hypervisor flag: $(grep -c hypervisor /proc/cpuinfo 2>/dev/null) 个核带 hypervisor 标志"'

# ---------- 6. 总线 / GPU ----------
h "6. PCI / USB / GPU"
if ! command -v lspci >/dev/null 2>&1; then
  sudo apt-get update -qq >/dev/null 2>&1 || true
  sudo apt-get install -y -qq pciutils usbutils >/dev/null 2>&1 || true
fi
block 'lspci -nn 2>/dev/null | head -40 || echo "(无 lspci)"'
block 'echo "显示设备:"; lspci 2>/dev/null | grep -iE "vga|3d|display" || echo "(未发现独立显示设备 / 仅虚拟显卡)"'
block 'lsusb 2>/dev/null || echo "(无 lsusb)"'
block 'command -v nvidia-smi >/dev/null && nvidia-smi || echo "(无 NVIDIA GPU / 无 nvidia-smi)"'

# ---------- 7. 网络 ----------
h "7. 网络"
block 'ip -br addr 2>/dev/null || ifconfig -a 2>/dev/null'
block 'echo "路由表:"; ip route 2>/dev/null | head -10'
block 'echo -n "公网出口 IP: "; curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "(获取失败)"; echo'
block 'echo -n "DNS 解析测试: "; getent hosts github.com >/dev/null 2>&1 && echo OK || echo FAIL'

# ---------- 8. 预装软件版本 ----------
h "8. 预装工具版本"
block 'for c in gcc g++ make cmake python3 pip3 node npm yarn docker go java dotnet rustc git jq; do printf "%-8s: " "$c"; if command -v "$c" >/dev/null 2>&1; then "$c" --version 2>&1 | head -1; else echo "(未安装)"; fi; done'
block 'echo "已安装包数量: $(dpkg -l 2>/dev/null | grep -c "^ii")"; echo "Docker:"; docker info --format "{{.ServerVersion}} / {{.Driver}} / {{.OperatingSystem}}" 2>/dev/null || echo "(docker 不可用)"'

# ---------- 9. Actions 环境 ----------
h "9. Actions 运行环境变量"
block 'env | grep -E "^(RUNNER_|GITHUB_|ImageOS|ImageVersion|ACTIONS_)" | grep -viE "(token|secret|key|password)" | sort'

# ---------- 10. 性能粗测 ----------
h "10. 性能粗测"
block 'echo "单线程 sha256 (1GB 数据, 3 次取最快):"; for i in 1 2 3; do /usr/bin/time -f "  %e 秒" bash -c "head -c 1073741824 /dev/zero | sha256sum > /dev/null" 2>&1 | tail -1; done'
block 'echo "磁盘写入 (512MB):"; /usr/bin/time -f "  写入 %e 秒" dd if=/dev/zero of=/tmp/ddtest bs=1M count=512 conv=fdatasync 2>&1 | tail -2; rm -f /tmp/ddtest'

printf '\n---\n报告生成完毕: %s\n' "$OUT" >>"$OUT"
echo "报告已写入: $OUT"
