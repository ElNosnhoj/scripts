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

