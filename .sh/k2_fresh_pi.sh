#!/bin/bash
# ================================================================
# helpers
# ================================================================
DEBUG="${DEBUG:-0}"   # 0 = hide output, 1 = show output
export DEBUG
run() { if [[ $DEBUG -eq 1 ]]; then "$@"; else "$@" > /dev/null 2>&1; fi }
[[ $DEBUG -eq 1 ]] && REDIR="" || REDIR="> /dev/null 2>&1"

print() {
    local txt="$1" fg="$2" bg="$3" esc="" reset="\e[0m" no_newline=${4:-0}
    local map=(black red green yellow blue magenta cyan white)

    build_code() {
        local c="$1" type="$2" base=""
        [[ -z "$c" ]] && return
        if [[ "$c" =~ ^#([A-Fa-f0-9]{6})$ ]]; then
            local r=$((16#${c:1:2})) g=$((16#${c:3:2})) b=$((16#${c:5:2}))
            esc+="\e[${type};2;${r};${g};${b}m"
        elif [[ "$c" =~ ^[0-9]+$ ]]; then
            esc+="\e[${type};5;${c}m"
        elif [[ "$c" == bright-* || "$c" == *-bright ]]; then
            c="${c#bright-}"; c="${c%-bright}"
            for i in "${!map[@]}"; do [[ ${map[$i]} == "$c" ]] && base=$i; done
            [[ $type == 38 ]] && esc+="\e[$((90+base))m" || esc+="\e[$((100+base))m"
        else
            for i in "${!map[@]}"; do [[ ${map[$i]} == "$c" ]] && base=$i; done
            [[ $type == 38 ]] && esc+="\e[$((30+base))m" || esc+="\e[$((40+base))m"
        fi
    }

    build_code "$fg" 38
    build_code "$bg" 48

    if [[ $no_newline -eq 1 ]]; then
        printf "%b%s%b" "$esc" "$txt" "$reset"
    else
        printf "%b%s%b\n" "$esc" "$txt" "$reset"
    fi
}
prompt_yes_no() {
    local txt="$1" fg="$2" bg="$3"
    local yn
    while true; do
        print "$txt (y/n): " "$fg" "$bg" 1  # 1 = no newline
        read yn
        yn="${yn:-n}"  # default to "n" if empty
        case $yn in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) print " Please answer yes (y) or no (n). " "white" "red" ;;
        esac
    done
}

spinner() {
    local pid=$1
    local message=$2
    local delay=0.1
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

    tput civis 2>/dev/null || true  # hide cursor
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\033[s"
        printf "\033[999;0H"
        printf "\033[2K"
        printf "\e[35m%s\e[0m %s" "${frames[$i]}" "$message"
        printf "\033[u"

        i=$(((i + 1) % ${#frames[@]}))
        sleep "$delay"
    done

    wait "$pid"
    local status=$?

    printf "\033[999;0H\033[2K"
    if [[ $status -eq 0 ]]; then
        printf "\e[32m✔\e[0m %s\n" "$message"
    else
        printf "\e[31m✖\e[0m %s\n" "$message"
    fi

    tput cnorm 2>/dev/null || true
    return $status
}

check_internet_access() {
    ping -c1 -w1 8.8.8.8 > /dev/null 2>&1 &
    local pid=$!
    spinner "$pid" "... Checking internet connectivity"
    local status=$?
    if [[ $status -ne 0 ]]; then
        print "No internet access" "white" "red"
        return 1
    fi
}

check_root_access() {
    if [ "$(id -u)" -eq 0 ]; then
        print "This script should not be run as root. Please run as a regular user with sudo permissions." white red
        exit 1
    fi
}

ask_reboot() {
    prompt_yes_no "Want to reboot now?" || false
    sudo reboot now
    exit 1
}

# ================================================================
# connect to ips
# ================================================================
connect_to_ips_ap() {
    # connect to IPS-AP?
    if prompt_yes_no "Connect to the IPS-AP WiFi network?" bright-yellow; then
        (
            set -e
            run sudo nmcli connection delete IPS-AP
            run sudo nmcli connection delete ips
            run sudo nmcli connection add type wifi ifname wlan0 con-name ips ssid "IPS-AP"
            run sudo nmcli connection modify ips wifi-sec.key-mgmt wpa-psk
            run sudo nmcli connection modify ips wifi-sec.psk 'twig-M3RHP!m'
            run sudo nmcli radio wifi on
            run sudo nmcli connection up ips
        ) &
        spinner $! "... Connecting to IPS-AP"
    fi

    # force IPS-AP priority
    if prompt_yes_no "Set IPS-AP as priority?" bright-yellow; then
        (
            set -e
            run sudo ip route add default via 192.168.5.1 dev wlan0 metric 50
            run sudo nmcli connection modify "ips" ipv4.route-metric 5
        ) &
        spinner $! "... Setting IPS-AP as highest priority WiFi network"
    fi
}

# ================================================================
# apt update + upgrade
# ================================================================
apt_update() {
    print "Updating package lists ... " bright-black
    check_internet_access || return 1
    (
        set -e
        run sudo apt update -y --fix-missing
    ) &
    spinner $! "Updating package lists"
}
apt_upgrade() {
    print "Upgrading system packages ... " bright-black
    check_internet_access || return 1
    run sudo apt upgrade -y --fix-missing --fix-broken &
    spinner $! "... Upgrading installed packages"
}

# ================================================================
# install docker
# ================================================================
install_docker() {
    print "Installing docker ... " bright-black
    check_internet_access || return 1
    if ! command -v docker >/dev/null 2>&1; then
        (
            set -e
            run curl -fsSL https://get.docker.com -o get-docker.sh
            run sudo sh get-docker.sh
            run sudo usermod -aG docker "$USER"
        ) &
        spinner $! "Installing Docker"
    else
        print "✔ ... Docker is already installed" bright-green ""
    fi
}

# ================================================================
# kiosk setup
# ================================================================
kiosk_setup(){
    print "Kiosk setup ... " bright-black
    check_internet_access || return 1
    bash <(curl -s https://raw.githubusercontent.com/ElNosnhoj/scripts/refs/heads/main/.sh/pi_kiosk.sh)
}

# ================================================================
# choice!
# ================================================================
walkthrough() {
    connect_to_ips_ap
    prompt_yes_no "Update package list?" bright-yellow && apt_update
    prompt_yes_no "Upgrade packages?" bright-yellow && apt_upgrade
    prompt_yes_no "Install docker?" bright-yellow && install_docker
    prompt_yes_no "Setup Kiosk mode?" bright-yellow && kiosk_setup
}

choice() {
    
    print "=================================" bright-green
    print "Select an option:" bright-green
    print "0) Walkthrough" bright-yellow
    print "1) Connect to IPS-AP" bright-yellow
    print "2) Check Internet connectivity" bright-yellow
    print "3) Update packages" bright-yellow
    print "4) Upgrade packages" bright-yellow
    print "5) Install Docker" bright-yellow
    print "6) Kiosk setup" bright-yellow
    print "x) Exit" bright-red
    echo
    print "Enter your choice (0): " "" "" 1
    read choice
    choice=${choice:-999}

    case "$choice" in
        [0]) walkthrough ;;
        [1]) connect_to_ips_ap ;;
        [2]) check_internet_access ;;
        [3]) apt_update ;;
        [4]) apt_upgrade ;;
        [5]) install_docker ;;
        [6]) kiosk_setup ;;
        [Xx])
            print "Exiting setup. Goodbye!" bright-green
            exit 0
            ;;
        *)
            print "Invalid option, please try again." white red
            choice
            ;;
    esac


    echo
    echo
}

print "======= K2 Fresh Pi Setup =======" bright-green
while true; do
    choice
done
