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
# install wayland+labwc
# ================================================================
install_wayland_labwc() {
    prompt_yes_no "Install Wayland and labwc packages?" bright-yellow || return
    print "Installing wayland and labwc ... " bright-black
    check_internet_access || return 1
    run sudo apt install --fix-missing --fix-broken --no-install-recommends -y labwc wlr-randr seatd &
    spinner $! "... Installing Wayland packages"
}

# ================================================================
# install chromium
# ================================================================
install_chromium() {
    prompt_yes_no "Install Chromium?" bright-yellow || return
    print "Installing chromium ... " bright-black

    # check for chromium packages
    local CHROMIUM_PKG=""
    if apt-cache show chromium >/dev/null 2>&1; then
        CHROMIUM_PKG="chromium"
    elif apt-cache show chromium-browser >/dev/null 2>&1; then
        CHROMIUM_PKG="chromium-browser"
    fi

    if [ -z "$CHROMIUM_PKG" ]; then
        print "No chromium package found in APT. You may need to enable the appropriate repository or install manually." bright-yellow
        return 1
    else
        run sudo apt install --fix-missing --fix-broken --no-install-recommends -y $CHROMIUM_PKG &
        spinner $! "... Installing Chromium browser"
    fi
    
}


# ================================================================
# install+autostart+setup greetd
# ================================================================
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo "~$CURRENT_USER")
install_greetd_service() {
    prompt_yes_no "Install and start greetd service?" bright-yellow || return
    print "Installing+configuring greetd for labwc autostart ... " bright-black
    run sudo apt install --fix-missing --fix-broken -y greetd & spinner $! "... Installing greetd"
    (
        set -e
        run sudo mkdir -p /etc/greetd
        run sudo bash -c "cat <<EOL > /etc/greetd/config.toml
[terminal]
vt = 7
[default_session]
command = \"/usr/bin/labwc\"
user = \"$CURRENT_USER\"
EOL"
        run sudo systemctl enable greetd
        run sudo systemctl start greetd
        run sudo systemctl set-default graphical.target
    ) & 
    spinner $! "... configuring and starting greetd"
}

create_labwc_autostart() {
    prompt_yes_no "Install+configure auto start of labwc?" bright-yellow || return

    print "Enter the URL to open in Chromium [default: https://webglsamples.org/aquarium/aquarium.html]: " bright-yellow "" 1
    read USER_URL
    USER_URL="${USER_URL:-https://webglsamples.org/aquarium/aquarium.html}"

    local INCOGNITO_FLAG=""
    if prompt_yes_no "Start browser in incognito mode?" bright-yellow; then
        INCOGNITO_FLAG="--incognito "
    fi

    local AUTOSTART_DIR="$HOME/.config/labwc"
    local AUTOSTART_FILE="$AUTOSTART_DIR/autostart"
    mkdir -p "$AUTOSTART_DIR"
    touch "$AUTOSTART_FILE"

    local CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
    if [ -z "$CHROMIUM_BIN" ]; then
        CHROMIUM_BIN="/usr/bin/chromium"
        print "Warning: couldn't find chromium binary in PATH. Using $CHROMIUM_BIN — adjust if needed." "white" "red"
    fi

    if grep -q -E "chromium|chromium-browser" "$AUTOSTART_FILE" 2>/dev/null; then
        print "Chromium autostart entry already exists in $AUTOSTART_FILE." bright-green
    else
        print "Adding Chromium to labwc autostart script..." bright-black
        echo "$CHROMIUM_BIN ${INCOGNITO_FLAG}--autoplay-policy=no-user-gesture-required --kiosk $USER_URL &" >> "$AUTOSTART_FILE"
        print "✔ labwc autostart script created/updated at $AUTOSTART_FILE." bright-green
    fi
}

# ================================================================
# Screen resolution
# ================================================================
configure_resolution() {
    prompt_yes_no "Set screen resolution in cmdline.txt and labwc autostart?" bright-yellow || return

    if ! command -v edid-decode &>/dev/null; then
        print "Installing required tool edid-decode..." bright-black
        run sudo apt install --fix-missing --fix-broken -y edid-decode &
        spinner $! "Installing edid-decode"
    fi

    local EDID_PATH=""
    [[ -r /sys/class/drm/card1-HDMI-A-1/edid ]] && EDID_PATH="/sys/class/drm/card1-HDMI-A-1/edid"
    [[ -r /sys/class/drm/card0-HDMI-A-1/edid ]] && EDID_PATH="/sys/class/drm/card0-HDMI-A-1/edid"

    local available_resolutions=()
    if [ -n "$EDID_PATH" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ([0-9]+)x([0-9]+)[[:space:]]+([0-9]+\.[0-9]+|[0-9]+)\ Hz ]]; then
                available_resolutions+=("${BASH_REMATCH[1]}x${BASH_REMATCH[2]}@${BASH_REMATCH[3]}")
            fi
        done <<< "$(sudo cat "$EDID_PATH" | edid-decode 2>/dev/null || true)"
    fi
    [[ ${#available_resolutions[@]} -eq 0 ]] && available_resolutions=("1920x1080@60" "1280x720@60" "1024x768@60" "1600x900@60" "1366x768@60")

    print "Please choose a resolution:" bright-cyan
    select RESOLUTION in "${available_resolutions[@]}"; do
        [[ -n "$RESOLUTION" ]] && { print "You selected $RESOLUTION" bright-green; break; }
        print "Invalid selection, please try again." white red
    done

    local CMDLINE_FILE="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_FILE" ] && ! grep -q "video=" "$CMDLINE_FILE"; then
        sudo sed -i "1s/^/video=HDMI-A-1:$RESOLUTION /" "$CMDLINE_FILE"
        print "✔ Resolution added to cmdline.txt" bright-green
    fi

    local AUTOSTART_FILE="$HOME_DIR/.config/labwc/autostart"
    mkdir -p "$(dirname "$AUTOSTART_FILE")"
    touch "$AUTOSTART_FILE"
    if ! grep -q "wlr-randr --output HDMI-A-1 --mode $RESOLUTION" "$AUTOSTART_FILE" 2>/dev/null; then
        echo "wlr-randr --output HDMI-A-1 --mode $RESOLUTION" >> "$AUTOSTART_FILE"
        print "✔ Resolution command added to labwc autostart" bright-green
    fi
}

# ================================================================
# Screen rotation
# ================================================================
configure_rotation() {
    prompt_yes_no "Set screen orientation (rotation)?" bright-yellow || return

    local orientations=("normal (0°)" "90° clockwise" "180°" "270° clockwise")
    local transform_values=("normal" "90" "180" "270")
    print "Please choose an orientation:" bright-cyan
    select orientation in "${orientations[@]}"; do
        [[ -n "$orientation" ]] && { TRANSFORM="${transform_values[$((REPLY-1))]}"; print "You selected $orientation" bright-green; break; }
        print "Invalid selection, please try again." white red
    done

    local AUTOSTART_FILE="$HOME_DIR/.config/labwc/autostart"
    mkdir -p "$(dirname "$AUTOSTART_FILE")"
    touch "$AUTOSTART_FILE"
    if ! grep -q "wlr-randr.*--transform" "$AUTOSTART_FILE" 2>/dev/null; then
        echo "wlr-randr --output HDMI-A-1 --transform $TRANSFORM" >> "$AUTOSTART_FILE"
        print "✔ Screen orientation added to labwc autostart" bright-green
    fi
}

# ================================================================
# Force audio to HDMI
# ================================================================
force_hdmi_audio() {
    prompt_yes_no "Force audio output to HDMI?" bright-yellow || return

    local CONFIG_TXT="/boot/firmware/config.txt"
    [ ! -f "$CONFIG_TXT" ] && { print "$CONFIG_TXT not found — skipping audio configuration." bright-yellow; return; }

    if grep -q "^dtparam=audio=" "$CONFIG_TXT"; then
        sudo sed -i 's/^dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT"
    elif grep -q "^#dtparam=audio=" "$CONFIG_TXT"; then
        sudo sed -i 's/^#dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT"
    else
        sudo bash -c "echo 'dtparam=audio=off' >> '$CONFIG_TXT'"
    fi
    print "✔ Audio parameter set to force HDMI output!" bright-green
}

# ================================================================
# Main walkthrough
# ================================================================
walkthrough() {
    install_wayland_labwc
    install_chromium
    install_greetd_service
    create_labwc_autostart
    configure_resolution
    configure_rotation
    force_hdmi_audio
    ask_reboot
}
check_root_access
walkthrough