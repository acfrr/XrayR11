#!/bin/bash
#====================================================
# XrayR 一键安装脚本
# 适配低内存机器 (128MB+ RAM)
# Repo: https://github.com/acfrr/XrayR11
#====================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

# 检测系统
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue 2>/dev/null | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "alpine"; then
    release="alpine"
elif cat /proc/version 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version 2>/dev/null | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# 检测架构
arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi
echo "架构: ${arch}"

XRAYR_REPO="acfrr/XrayR11"
XRAYR_INSTALL_DIR="/usr/local/XrayR"
XRAYR_CONFIG_DIR="/etc/XrayR"
XRAYR_LOG_DIR="/var/log/XrayR"

# 检查运行状态: 0=运行中, 1=未运行, 2=未安装
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_base() {
    if [[ x"${release}" == x"alpine" ]]; then
        apk add --no-cache wget curl unzip tar socat bash
    elif [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm -rf /usr/local/XrayR/
    fi

    mkdir -p /usr/local/XrayR/
    cd /usr/local/XrayR/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/${XRAYR_REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            last_version="v0.9.5"
            echo -e "${yellow}GitHub API 不可用，使用默认版本: ${last_version}${plain}"
        fi
        echo -e "检测到 XrayR 最新版本：${last_version}，开始安装"
        wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip \
            https://github.com/${XRAYR_REPO}/releases/download/${last_version}/XrayR-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR 失败，请确认 Release 存在${plain}"
            exit 1
        fi
    else
        if [[ $1 == v* ]]; then last_version=$1; else last_version="v"$1; fi
        url="https://github.com/${XRAYR_REPO}/releases/download/${last_version}/XrayR-linux-${arch}.zip"
        echo -e "开始安装 XrayR ${last_version}"
        wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR ${last_version} 失败，请确认 Release 存在${plain}"
            exit 1
        fi
    fi

    unzip -o -q XrayR-linux.zip
    rm -f XrayR-linux.zip
    chmod +x XrayR

    mkdir -p /etc/XrayR/
    mkdir -p /var/log/XrayR/

    # 安装 systemd 服务
    systemctl unmask XrayR 2>/dev/null
    rm -f /etc/systemd/system/XrayR.service
    cat > /etc/systemd/system/XrayR.service << EOF
[Unit]
Description=XrayR Service
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10
Nice=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # 复制数据文件
    cp -f geoip.dat /etc/XrayR/ 2>/dev/null || true
    cp -f geosite.dat /etc/XrayR/ 2>/dev/null || true

    # 复制配置文件 (不覆盖已有)
    if [[ ! -f /etc/XrayR/config.yml ]]; then
        cp -f config.yml /etc/XrayR/ 2>/dev/null || true
        if [[ ! -f /etc/XrayR/config.yml ]]; then
            cat > /etc/XrayR/config.yml << 'YMLCONF'
Log:
  Level: warning
  AccessPath: /var/log/XrayR/access.log
  ErrorPath: /var/log/XrayR/error.log
ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 32
Nodes:
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "https://your-panel.com"
      ApiKey: "your-api-key"
      NodeID: 1
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      SpeedLimit: 0
      DeviceLimit: 0
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false
      EnableFallback: false
      CertConfig:
        CertMode: none
YMLCONF
        fi
    else
        echo -e "${yellow}已存在配置文件，跳过覆盖${plain}"
    fi

    cp -n dns.json /etc/XrayR/ 2>/dev/null || true
    cp -n route.json /etc/XrayR/ 2>/dev/null || true
    cp -n custom_outbound.json /etc/XrayR/ 2>/dev/null || true
    cp -n custom_inbound.json /etc/XrayR/ 2>/dev/null || true
    cp -n rulelist /etc/XrayR/ 2>/dev/null || true

    # 安装管理脚本 (内嵌)
    cat > /usr/bin/XrayR << 'XRAYRCMD'
#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

XRAYR_BIN="/usr/local/XrayR/XrayR"
XRAYR_CONFIG="/etc/XrayR/config.yml"
XRAYR_LOG="/var/log/XrayR/xrayr.log"

check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then return 0; else return 1; fi
}

show_status() {
    echo -e "${cyan}========================================${plain}"
    echo -e "${cyan}         XrayR 运行状态${plain}"
    echo -e "${cyan}========================================${plain}"
    check_status
    local status=$?
    if [[ $status == 0 ]]; then
        echo -e "状态:     ${green}运行中${plain}"
        local pid
        pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
        if [[ -n "$pid" && "$pid" != "0" ]]; then
            echo -e "PID:      $pid"
            if [[ -f /proc/$pid/status ]]; then
                local mem
                mem=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
                [[ -n "$mem" ]] && echo -e "内存:     $(( mem / 1024 )) MB"
            fi
        fi
    elif [[ $status == 1 ]]; then
        echo -e "状态:     ${red}未运行${plain}"
    else
        echo -e "状态:     ${red}未安装${plain}"
    fi
    local total_mem
    total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
    echo -e "系统内存: ${total_mem} MB"
    if [[ -f "$XRAYR_BIN" ]]; then
        echo -e "版本:     $("$XRAYR_BIN" version 2>/dev/null || echo "unknown")"
    fi
    echo -e "${cyan}========================================${plain}"
}

bbr_install() {
    echo -e "${cyan}========================================${plain}"
    echo -e "${cyan}  一键安装 BBR (最新内核)${plain}"
    echo -e "${cyan}========================================${plain}"

    local kernel_ver
    kernel_ver=$(uname -r 2>/dev/null | cut -d- -f1)
    echo -e "当前内核版本: ${yellow}${kernel_ver}${plain}"

    # Check if BBR is already enabled
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${green}BBR 已启用，无需重复安装${plain}"
        return
    fi

    echo -e "${yellow}正在启用 BBR...${plain}"

    # Enable BBR
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1

    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${green}BBR 启用成功!${plain}"
        echo -e "当前拥塞控制算法: ${green}${current_cc}${plain}"
        local qdisc
        qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        echo -e "当前队列算法:       ${green}${qdisc}${plain}"
    else
        echo -e "${yellow}内核版本 ${kernel_ver} 可能不支持 BBR${plain}"
        echo -e "${yellow}BBR 需要内核 4.9+，你可以在 XrayR 菜单中先升级内核${plain}"
    fi
}

show_menu() {
    echo -e "
  ${cyan}XrayR 管理脚本${plain}  ${yellow}v0.9.5${plain}
  ${green}0${plain}. 退出脚本
  ${cyan}————————————————————————${plain}
  ${green}1${plain}. 安装 XrayR
  ${green}2${plain}. 更新 XrayR
  ${green}3${plain}. 卸载 XrayR
  ${cyan}————————————————————————${plain}
  ${green}4${plain}. 启动 XrayR
  ${green}5${plain}. 停止 XrayR
  ${green}6${plain}. 重启 XrayR
  ${cyan}————————————————————————${plain}
  ${green}7${plain}. 查看状态
  ${green}8${plain}. 查看日志
  ${green}9${plain}. 实时日志
  ${cyan}————————————————————————${plain}
  ${green}10${plain}. 编辑配置
  ${green}11${plain}. 查看配置
  ${green}12${plain}. 一键安装 BBR (最新内核)
  ${cyan}————————————————————————${plain}
  ${green}13${plain}. 设置开机自启
  ${green}14${plain}. 取消开机自启
  ${cyan}————————————————————————${plain}
  ${green}15${plain}. 查看内存使用
  ${green}16${plain}. 低内存优化
  ${cyan}————————————————————————${plain}
 "
    echo && read -p "请输入选择 [0-16]: " num
    case "${num}" in
        0) exit 0 ;;
        1) bash <(curl -Ls https://raw.githubusercontent.com/acfrr/XrayR11/master/install.sh) ;;
        2)
            read -p "请输入版本号 (留空为最新版): " ver
            bash <(curl -Ls https://raw.githubusercontent.com/acfrr/XrayR11/master/install.sh) "$ver"
            ;;
        3)
            systemctl stop XrayR 2>/dev/null
            systemctl disable XrayR 2>/dev/null
            rm -f /etc/systemd/system/XrayR.service
            rm -rf /etc/systemd/system/XrayR.service.d/
            systemctl daemon-reload 2>/dev/null
            rm -rf /usr/local/XrayR/
            rm -rf /etc/XrayR/
            rm -f /usr/bin/XrayR /usr/bin/xrayr
            echo -e "${green}XrayR 已完全卸载${plain}"
            ;;
        4)
            systemctl start XrayR
            sleep 2
            check_status
            [[ $? == 0 ]] && echo -e "${green}XrayR 启动成功${plain}" || echo -e "${red}XrayR 启动失败，请使用 XrayR log 查看日志${plain}"
            ;;
        5)
            systemctl stop XrayR
            echo -e "${green}XrayR 已停止${plain}"
            ;;
        6)
            systemctl restart XrayR
            sleep 2
            check_status
            [[ $? == 0 ]] && echo -e "${green}XrayR 重启成功${plain}" || echo -e "${red}XrayR 重启失败，请使用 XrayR log 查看日志${plain}"
            ;;
        7) show_status ;;
        8)
            if [[ -f "$XRAYR_LOG" ]]; then
                echo -e "${cyan}=== XrayR 日志 (最后50行) ===${plain}"
                tail -n 50 "$XRAYR_LOG"
            elif command -v journalctl &>/dev/null; then
                journalctl -u XrayR --no-pager -n 50
            else
                echo -e "${red}未找到日志文件${plain}"
            fi
            ;;
        9)
            echo -e "${yellow}按 Ctrl+C 退出实时日志${plain}"
            [[ -f "$XRAYR_LOG" ]] && tail -f "$XRAYR_LOG" || journalctl -u XrayR -f
            ;;
        10)
            if [[ -f "$XRAYR_CONFIG" ]]; then
                local ed="${EDITOR:-vim}"
                command -v "$ed" &>/dev/null || { command -v vim &>/dev/null && ed="vim"; } || { command -v vi &>/dev/null && ed="vi"; } || { command -v nano &>/dev/null && ed="nano"; } || ed="cat"
                [[ "$ed" == "cat" ]] && cat "$XRAYR_CONFIG" || "$ed" "$XRAYR_CONFIG"
                echo -e "${green}配置已保存，使用 XrayR restart 生效${plain}"
            else
                echo -e "${red}配置文件不存在${plain}"
            fi
            ;;
        11) [[ -f "$XRAYR_CONFIG" ]] && cat "$XRAYR_CONFIG" || echo -e "${red}配置文件不存在${plain}" ;;
        12) bbr_install ;;
        13) systemctl enable XrayR && echo -e "${green}已设置开机自启${plain}" ;;
        14) systemctl disable XrayR && echo -e "${green}已取消开机自启${plain}" ;;
        15)
            echo -e "${cyan}=== 系统内存 ===${plain}"
            grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null | while read line; do echo "  $line"; done
            check_status 2>/dev/null
            if [[ $? == 0 ]]; then
                local pid
                pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
                if [[ -n "$pid" && "$pid" != "0" && -f /proc/$pid/status ]]; then
                    echo ""
                    echo -e "${cyan}=== XrayR 内存使用 ===${plain}"
                    grep -E "VmRSS|VmSize|VmSwap" /proc/$pid/status 2>/dev/null | while read line; do echo "  $line"; done
                fi
            fi
            local tm
            tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            [[ -n "$tm" && "$tm" -lt 128 ]] && echo -e "\n${yellow}系统内存低于128MB，建议运行 XrayR tune 进行优化${plain}"
            ;;
        16)
            echo -e "${yellow}正在应用低内存优化...${plain}"
            sysctl -w vm.swappiness=10 2>/dev/null || true
            local tm
            tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
            if [[ -n "$tm" && "$tm" -lt 262144 ]]; then
                local mem_limit="$(( tm / 2 ))KiB"
                mkdir -p /etc/systemd/system/XrayR.service.d/
                cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$mem_limit"
MemoryMax=$(( tm / 2 ))K
CPUQuota=50%
LMEOF
                systemctl daemon-reload
                echo -e "${green}已设置 GOMEMLIMIT=${mem_limit}${plain}"
            fi
            if [[ ! -f /proc/swaps ]] || [[ "$(wc -l < /proc/swaps)" -le 1 ]]; then
                echo -e "${yellow}提示：未检测到 swap，建议添加：${plain}"
                echo "  fallocate -l 256M /swapfile && chmod 600 /swapfile"
                echo "  mkswap /swapfile && swapon /swapfile"
            fi
            echo -e "${green}低内存优化完成${plain}"
            ;;
        *) echo -e "${red}请输入正确的数字 [0-16]${plain}" ;;
    esac
}

case "$1" in
    start)    systemctl start XrayR ;;
    stop)     systemctl stop XrayR ;;
    restart)  systemctl restart XrayR ;;
    status)   show_status ;;
    log|logs)
        [[ -f "$XRAYR_LOG" ]] && tail -n 50 "$XRAYR_LOG" || journalctl -u XrayR --no-pager -n 50 ;;
    live)
        [[ -f "$XRAYR_LOG" ]] && tail -f "$XRAYR_LOG" || journalctl -u XrayR -f ;;
    config)
        local ed="${EDITOR:-vim}"
        command -v "$ed" &>/dev/null || { command -v vim &>/dev/null && ed="vim"; } || { command -v vi &>/dev/null && ed="vi"; } || { command -v nano &>/dev/null && ed="nano"; } || ed="cat"
        [[ "$ed" == "cat" ]] && cat "$XRAYR_CONFIG" || "$ed" "$XRAYR_CONFIG" ;;
    show)  cat "$XRAYR_CONFIG" 2>/dev/null || echo -e "${red}配置文件不存在${plain}" ;;
    enable)   systemctl enable XrayR && echo -e "${green}已设置开机自启${plain}" ;;
    disable)  systemctl disable XrayR && echo -e "${green}已取消开机自启${plain}" ;;
    update)   bash <(curl -Ls https://raw.githubusercontent.com/acfrr/XrayR11/master/install.sh) "$2" ;;
    install)  bash <(curl -Ls https://raw.githubusercontent.com/acfrr/XrayR11/master/install.sh) ;;
    uninstall|un)
        systemctl stop XrayR 2>/dev/null
        systemctl disable XrayR 2>/dev/null
        rm -f /etc/systemd/system/XrayR.service
        rm -rf /etc/systemd/system/XrayR.service.d/
        systemctl daemon-reload 2>/dev/null
        rm -rf /usr/local/XrayR/ /etc/XrayR/
        rm -f /usr/bin/XrayR /usr/bin/xrayr
        echo -e "${green}XrayR 已完全卸载${plain}" ;;
    version)  [[ -f "$XRAYR_BIN" ]] && "$XRAYR_BIN" version || echo "XrayR 未安装" ;;
    bbr)      bbr_install ;;
    mem|memory)
        echo -e "${cyan}=== 系统内存 ===${plain}"
        grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null | while read line; do echo "  $line"; done
        check_status 2>/dev/null
        if [[ $? == 0 ]]; then
            local pid
            pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
            [[ -n "$pid" && "$pid" != "0" && -f /proc/$pid/status ]] && echo -e "\n${cyan}=== XrayR 内存 ===${plain}" && grep -E "VmRSS|VmSize" /proc/$pid/status 2>/dev/null
        fi ;;
    tune)
        sysctl -w vm.swappiness=10 2>/dev/null || true
        local tm
        tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [[ -n "$tm" && "$tm" -lt 262144 ]]; then
            mkdir -p /etc/systemd/system/XrayR.service.d/
            cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$(( tm / 2 ))KiB"
MemoryMax=$(( tm / 2 ))K
CPUQuota=50%
LMEOF
            systemctl daemon-reload
            echo -e "${green}已设置 GOMEMLIMIT=$(( tm / 2 ))KiB${plain}"
        fi
        echo -e "${green}低内存优化完成${plain}" ;;
    *)
        while true; do
            show_menu
            echo ""
            read -p "按 Enter 继续..."
        done ;;
esac
XRAYRCMD

    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
    chmod +x /usr/bin/xrayr 2>/dev/null || true

    systemctl daemon-reload
    systemctl stop XrayR 2>/dev/null
    systemctl enable XrayR

    cd "$cur_dir"
    rm -f install.sh

    echo -e "${green}XrayR ${last_version}${plain} 安装完成，已设置开机自启"

    # 如果是全新安装
    if [[ ! -f /etc/XrayR/config.yml ]]; then
        echo -e ""
        echo -e "全新安装，请先配置面板信息：${yellow}XrayR config${plain}"
    else
        systemctl start XrayR
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 启动成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请使用 XrayR log 查看日志${plain}"
        fi
    fi

    # 低内存机器检测 & 优化
    local total_mem
    total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
    if [[ -n "$total_mem" ]] && [[ "$total_mem" -le 256 ]]; then
        echo -e "\n${yellow}检测到低内存 (${total_mem}MB)，应用自动优化...${plain}"
        mkdir -p /etc/systemd/system/XrayR.service.d/
        cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$(( total_mem * 512 ))KiB"
MemoryMax=$(( total_mem * 512 ))K
CPUQuota=50%
LMEOF
        systemctl daemon-reload
        echo -e "${green}已自动设置内存限制${plain}"
    fi

    echo -e ""
    echo "XrayR 管理脚本使用方法 (兼容使用 xrayr 执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR live               - 实时日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 编辑配置文件"
    echo "XrayR show               - 查看配置文件内容"
    echo "XrayR install            - 安装 XrayR"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "XrayR bbr                - 一键安装 BBR"
    echo "XrayR mem                - 查看内存使用"
    echo "XrayR tune               - 低内存优化"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_XrayR $1
