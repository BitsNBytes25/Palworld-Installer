#!/bin/bash
#
# Install Game Server
#
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @AUTHOR  Drew Wort <drew@worttechnologies.tech>
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
# @WARLOCK-TITLE Palworld
# @WARLOCK-IMAGE media/palworld-1920x1080.webp
# @WARLOCK-ICON media/palworld-128x128.webp
# @WARLOCK-THUMBNAIL media/palworld-640x360.webp
#
# Supports:
#   Debian 12, 13
#   Ubuntu 24.04
#
# Requirements:
#   None
#
# TRMM Custom Fields:
#   None
#
# Syntax:
#   --uninstall  - Perform an uninstallation
#   --dir=<str> - Use a custom installation directory instead of the default (optional)
#   --skip-firewall  - Do not install or configure a system firewall
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#   --port=<int> - Specify a custom port for the game server to use DEFAULT=8211
#   --threads=<int> - Specify the number of threads to allocate to the game server DEFAULT=AUTO
#
# Changelog:
#   20251127 - Migrated to new Warlock baseline
#   20250331 - Implement management script ported from ARK SA
#   20250125 - Initial release

############################################
## Parameter Configuration
############################################

# Name of the game (used to create the directory)
INSTALLER_VERSION="v20251129"
GAME="Palworld"
GAME_DESC="Palworld Dedicated Server"
REPO="BitsNBytes25/Palworld-Installer"
WARLOCK_GUID="e4cd1462-87ec-213b-f0fa-7e2a1ba72e2d"
STEAM_ID="2394010"
GAME_USER="steam"
GAME_DIR="/home/${GAME_USER}/${GAME}"
GAME_SERVICE="palworld-server"

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --uninstall  - Perform an uninstallation
    --dir=<str> - Use a custom installation directory instead of the default (optional)
    --skip-firewall  - Do not install or configure a system firewall
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
    --port=<int> - Specify a custom port for the game server to use DEFAULT=8211
    --threads=<int> - Specify the number of threads to allocate to the game server DEFAULT=AUTO

Please ensure to run this script as root (or at least with sudo)

@LICENSE AGPLv3
EOD
  exit 1
}

# Parse arguments
MODE_UNINSTALL=0
OVERRIDE_DIR=""
SKIP_FIREWALL=0
NONINTERACTIVE=0
PORT="8211"
THREADS="AUTO"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--uninstall) MODE_UNINSTALL=1; shift 1;;
		--dir=*)
			OVERRIDE_DIR="${1#*=}";
			[ "${OVERRIDE_DIR:0:1}" == "'" ] && [ "${OVERRIDE_DIR:0-1}" == "'" ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			[ "${OVERRIDE_DIR:0:1}" == '"' ] && [ "${OVERRIDE_DIR:0-1}" == '"' ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			shift 1;;
		--skip-firewall) SKIP_FIREWALL=1; shift 1;;
		--non-interactive) NONINTERACTIVE=1; shift 1;;
		--port=*)
			PORT="${1#*=}";
			[ "${PORT:0:1}" == "'" ] && [ "${PORT:0-1}" == "'" ] && PORT="${PORT:1:-1}"
			[ "${PORT:0:1}" == '"' ] && [ "${PORT:0-1}" == '"' ] && PORT="${PORT:1:-1}"
			shift 1;;
		--threads=*)
			THREADS="${1#*=}";
			[ "${THREADS:0:1}" == "'" ] && [ "${THREADS:0-1}" == "'" ] && THREADS="${THREADS:1:-1}"
			[ "${THREADS:0:1}" == '"' ] && [ "${THREADS:0-1}" == '"' ] && THREADS="${THREADS:1:-1}"
			shift 1;;
		-h|--help) usage;;
	esac
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
##
# Get which firewall is enabled,
# or "none" if none located
function get_enabled_firewall() {
	if [ "$(systemctl is-active firewalld)" == "active" ]; then
		echo "firewalld"
	elif [ "$(systemctl is-active ufw)" == "active" ]; then
		echo "ufw"
	elif [ "$(systemctl is-active iptables)" == "active" ]; then
		echo "iptables"
	else
		echo "none"
	fi
}

##
# Get which firewall is available on the local system,
# or "none" if none located
#
# CHANGELOG:
#   2025.04.10 - Switch from "systemctl list-unit-files" to "which" to support older systems
function get_available_firewall() {
	if which -s firewall-cmd; then
		echo "firewalld"
	elif which -s ufw; then
		echo "ufw"
	elif systemctl list-unit-files iptables.service &>/dev/null; then
		echo "iptables"
	else
		echo "none"
	fi
}
##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_debian() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'debian' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'debian' ]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_ubuntu() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_rhel() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'rhel' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'fedora' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'centos' ]]; then echo 1; return; fi
		if [ "$ID" == 'rhel' ]; then echo 1; return; fi
		if [ "$ID" == 'fedora' ]; then echo 1; return; fi
		if [ "$ID" == 'centos' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_suse() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'suse' ]]; then echo 1; return; fi
		if [ "$ID" == 'suse' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_arch() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'arch' ]]; then echo 1; return; fi
		if [ "$ID" == 'arch' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_bsd() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_macos() {
	if [ "$(uname -s)" == 'Darwin' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Install a package with the system's package manager.
#
# Uses Redhat's yum, Debian's apt-get, and SuSE's zypper.
#
# Usage:
#
# ```syntax-shell
# package_install apache2 php7.0 mariadb-server
# ```
#
# @param $1..$N string
#        Package, (or packages), to install.  Accepts multiple packages at once.
#
#
# CHANGELOG:
#   2025.04.10 - Set Debian frontend to noninteractive
#
function package_install (){
	echo "package_install: Installing $*..."

	TYPE_BSD="$(os_like_bsd)"
	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_RHEL="$(os_like_rhel)"
	TYPE_ARCH="$(os_like_arch)"
	TYPE_SUSE="$(os_like_suse)"

	if [ "$TYPE_BSD" == 1 ]; then
		pkg install -y $*
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif [ "$TYPE_RHEL" == 1 ]; then
		yum install -y $*
	elif [ "$TYPE_ARCH" == 1 ]; then
		pacman -Syu --noconfirm $*
	elif [ "$TYPE_SUSE" == 1 ]; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		exit 1
	fi
}
##
# Add an "allow" rule to the firewall in the INPUT chain
#
# Arguments:
#   --port <port>       Port(s) to allow
#   --source <source>   Source IP to allow (default: any)
#   --zone <zone>       Zone to allow (default: public)
#   --tcp|--udp         Protocol to allow (default: tcp)
#   --proto <tcp|udp>   Protocol to allow (alternative method)
#   --comment <comment> (only UFW) Comment for the rule
#
# Specify multiple ports with `--port '#,#,#'` or a range `--port '#:#'`
#
# CHANGELOG:
#   2025.11.23 - Use return codes instead of exit to allow the caller to handle errors
#   2025.04.10 - Add "--proto" argument as alternative to "--tcp|--udp"
#
function firewall_allow() {
	# Defaults and argument processing
	local PORT=""
	local PROTO="tcp"
	local SOURCE="any"
	local FIREWALL=$(get_available_firewall)
	local ZONE="public"
	local COMMENT=""
	while [ $# -ge 1 ]; do
		case $1 in
			--port)
				shift
				PORT=$1
				;;
			--tcp|--udp)
				PROTO=${1:2}
				;;
			--proto)
				shift
				PROTO=$1
				;;
			--source|--from)
				shift
				SOURCE=$1
				;;
			--zone)
				shift
				ZONE=$1
				;;
			--comment)
				shift
				COMMENT=$1
				;;
			*)
				PORT=$1
				;;
		esac
		shift
	done

	if [ "$PORT" == "" -a "$ZONE" != "trusted" ]; then
		echo "firewall_allow: No port specified!" >&2
		return 2
	fi

	if [ "$PORT" != "" -a "$ZONE" == "trusted" ]; then
		echo "firewall_allow: Trusted zones do not use ports!" >&2
		return 2
	fi

	if [ "$ZONE" == "trusted" -a "$SOURCE" == "any" ]; then
		echo "firewall_allow: Trusted zones require a source!" >&2
		return 2
	fi

	if [ "$FIREWALL" == "ufw" ]; then
		if [ "$SOURCE" == "any" ]; then
			echo "firewall_allow/UFW: Allowing $PORT/$PROTO from any..."
			ufw allow proto $PROTO to any port $PORT comment "$COMMENT"
		elif [ "$ZONE" == "trusted" ]; then
			echo "firewall_allow/UFW: Allowing all connections from $SOURCE..."
			ufw allow from $SOURCE comment "$COMMENT"
		else
			echo "firewall_allow/UFW: Allowing $PORT/$PROTO from $SOURCE..."
			ufw allow from $SOURCE proto $PROTO to any port $PORT comment "$COMMENT"
		fi
		return 0
	elif [ "$FIREWALL" == "firewalld" ]; then
		if [ "$SOURCE" != "any" ]; then
			# Firewalld uses Zones to specify sources
			echo "firewall_allow/firewalld: Adding $SOURCE to $ZONE zone..."
			firewall-cmd --zone=$ZONE --add-source=$SOURCE --permanent
		fi

		if [ "$PORT" != "" ]; then
			echo "firewall_allow/firewalld: Allowing $PORT/$PROTO in $ZONE zone..."
			if [[ "$PORT" =~ ":" ]]; then
				# firewalld expects port ranges to be in the format of "#-#" vs "#:#"
				local DPORTS="${PORT/:/-}"
				firewall-cmd --zone=$ZONE --add-port=$DPORTS/$PROTO --permanent
			elif [[ "$PORT" =~ "," ]]; then
				# Firewalld cannot handle multiple ports all that well, so split them by the comma
				# and run the add command separately for each port
				local DPORTS="$(echo $PORT | sed 's:,: :g')"
				for P in $DPORTS; do
					firewall-cmd --zone=$ZONE --add-port=$P/$PROTO --permanent
				done
			else
				firewall-cmd --zone=$ZONE --add-port=$PORT/$PROTO --permanent
			fi
		fi

		firewall-cmd --reload
		return 0
	elif [ "$FIREWALL" == "iptables" ]; then
		echo "firewall_allow/iptables: WARNING - iptables is untested"
		# iptables doesn't natively support multiple ports, so we have to get creative
		if [[ "$PORT" =~ ":" ]]; then
			local DPORTS="-m multiport --dports $PORT"
		elif [[ "$PORT" =~ "," ]]; then
			local DPORTS="-m multiport --dports $PORT"
		else
			local DPORTS="--dport $PORT"
		fi

		if [ "$SOURCE" == "any" ]; then
			echo "firewall_allow/iptables: Allowing $PORT/$PROTO from any..."
			iptables -A INPUT -p $PROTO $DPORTS -j ACCEPT
		else
			echo "firewall_allow/iptables: Allowing $PORT/$PROTO from $SOURCE..."
			iptables -A INPUT -p $PROTO $DPORTS -s $SOURCE -j ACCEPT
		fi
		iptables-save > /etc/iptables/rules.v4
		return 0
	elif [ "$FIREWALL" == "none" ]; then
		echo "firewall_allow: No firewall detected" >&2
		return 1
	else
		echo "firewall_allow: Unsupported or unknown firewall" >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		return 1
	fi
}
##
# Simple download utility function
#
# Uses either cURL or wget based on which is available
#
# Downloads the file to a temp location initially, then moves it to the final destination
# upon a successful download to avoid partial files.
#
# Returns 0 on success, 1 on failure
#
# CHANGELOG:
#   2025.11.23 - Download to a temp location to verify download was successful
#              - use which -s for cleaner checks
#   2025.11.09 - Initial version
#
function download() {
	local SOURCE="$1"
	local DESTINATION="$2"
	local TMP=$(mktemp)

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if which -s curl; then
		if curl -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif which -s wget; then
		if wget -q "$SOURCE" -O "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: wget failed to download $SOURCE" >&2
			return 1
		fi
	else
		echo "download: Neither curl nor wget is installed, cannot download!" >&2
		return 1
	fi
}
##
# Determine if the current shell session is non-interactive.
#
# Checks NONINTERACTIVE, CI, DEBIAN_FRONTEND, TERM, and TTY status.
#
# Returns 0 (true) if non-interactive, 1 (false) if interactive.
#
# CHANGELOG:
#   2025.11.23 - Initial version
#
function is_noninteractive() {
	# explicit flags
	case "${NONINTERACTIVE:-}${CI:-}" in
		1*|true*|TRUE*|True*|*CI* ) return 0 ;;
	esac

	# debian frontend
	if [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then
		return 0
	fi

	# dumb terminal or no tty on stdin/stdout
	if [ "${TERM:-}" = "dumb" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
		return 0
	fi

	return 1
}

##
# Prompt user for a text response
#
# Arguments:
#   --default="..."   Default text to use if no response is given
#
# Returns:
#   text as entered by user
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.01.01 - Initial version
#
function prompt_text() {
	local DEFAULT=""
	local PROMPT="Enter some text"
	local RESPONSE=""

	while [ $# -ge 1 ]; do
		case $1 in
			--default=*) DEFAULT="${1#*=}";;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	echo -n '> : ' >&2

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		echo $DEFAULT
		return
	fi

	read RESPONSE
	if [ "$RESPONSE" == "" ]; then
		echo "$DEFAULT"
	else
		echo "$RESPONSE"
	fi
}

##
# Prompt user for a yes or no response
#
# Arguments:
#   --invert            Invert the response (yes becomes 0, no becomes 1)
#   --default-yes       Default to yes if no response is given
#   --default-no        Default to no if no response is given
#   -q                  Quiet mode (no output text after response)
#
# Returns:
#   1 for yes, 0 for no (or inverted if --invert is set)
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.11.09 - Add -q (quiet) option to suppress output after prompt (and use return value)
#   2025.01.01 - Initial version
#
function prompt_yn() {
	local TRUE=0 # Bash convention: 0 is success/true
	local YES=1
	local FALSE=1 # Bash convention: non-zero is failure/false
	local NO=0
	local DEFAULT="n"
	local DEFAULT_CODE=1
	local PROMPT="Yes or no?"
	local RESPONSE=""
	local QUIET=0

	while [ $# -ge 1 ]; do
		case $1 in
			--invert) YES=0; NO=1 TRUE=1; FALSE=0;;
			--default-yes) DEFAULT="y";;
			--default-no) DEFAULT="n";;
			-q) QUIET=1;;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	if [ "$DEFAULT" == "y" ]; then
		DEFAULT="$YES"
		DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT="$NO"
		DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		if [ $QUIET -eq 0 ]; then
			echo $DEFAULT
		fi
		return $DEFAULT_CODE
	fi

	read RESPONSE
	case "$RESPONSE" in
		[yY]*)
			if [ $QUIET -eq 0 ]; then
				echo $YES
			fi
			return $TRUE;;
		[nN]*)
			if [ $QUIET -eq 0 ]; then
				echo $NO
			fi
			return $FALSE;;
		*)
			if [ $QUIET -eq 0 ]; then
				echo $DEFAULT
			fi
			return $DEFAULT_CODE;;
	esac
}
##
# Print a header message
#
# CHANGELOG:
#   2025.11.09 - Port from _common to bz_eval_tui
#   2024.12.25 - Initial version
#
function print_header() {
	local header="$1"
	echo "================================================================================"
	printf "%*s\n" $(((${#header}+80)/2)) "$header"
    echo ""
}
##
# Get the operating system version
#
# Just the major version number is returned
#
function os_version() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		local _V="$(uname -K)"
		if [ ${#_V} -eq 6 ]; then
			echo "${_V:0:1}"
		elif [ ${#_V} -eq 7 ]; then
			echo "${_V:0:2}"
		fi

	elif [ -f '/etc/os-release' ]; then
		local VERS="$(egrep '^VERSION_ID=' /etc/os-release | sed 's:VERSION_ID=::')"

		if [[ "$VERS" =~ '"' ]]; then
			# Strip quotes around the OS name
			VERS="$(echo "$VERS" | sed 's:"::g')"
		fi

		if [[ "$VERS" =~ \. ]]; then
			# Remove the decimal point and everything after
			# Trims "24.04" down to "24"
			VERS="${VERS/\.*/}"
		fi

		if [[ "$VERS" =~ "v" ]]; then
			# Remove the "v" from the version
			# Trims "v24" down to "24"
			VERS="${VERS/v/}"
		fi

		echo "$VERS"

	else
		echo 0
	fi
}

##
# Install SteamCMD
function install_steamcmd() {
	echo "Installing SteamCMD..."

	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_UBUNTU="$(os_like_ubuntu)"
	OS_VERSION="$(os_version)"

	# Preliminary requirements
	if [ "$TYPE_UBUNTU" == 1 ]; then
		add-apt-repository -y multiverse
		dpkg --add-architecture i386
		apt update

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		apt install -y steamcmd
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		dpkg --add-architecture i386
		apt update

		if [ "$OS_VERSION" -le 12 ]; then
			apt install -y software-properties-common apt-transport-https dirmngr ca-certificates lib32gcc-s1

			# Enable "non-free" repos for Debian (for steamcmd)
			# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
			add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free
			if [ $? -ne 0 ]; then
				echo "Workaround failed to add non-free repos, trying new method instead"
				apt-add-repository -y non-free
			fi
		else
			# Debian Trixie and later
			if [ -e /etc/apt/sources.list ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list
				fi
			elif [ -e /etc/apt/sources.list.d/debian.sources ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list.d/debian.sources; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list.d/debian.sources
				fi
			else
				echo "Could not find a sources.list file to enable non-free repos" >&2
				exit 1
			fi
		fi

		# Install steam repo
		download http://repo.steampowered.com/steam/archive/stable/steam.gpg /usr/share/keyrings/steam.gpg
		echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		# Install steam binary and steamcmd
		apt update
		apt install -y steamcmd
	else
		echo 'Unsupported or unknown OS' >&2
		exit 1
	fi
}

##
# Install UFW
#
function install_ufw() {
	if [ "$(os_like_rhel)" == 1 ]; then
		# RHEL/CentOS requires EPEL to be installed first
		package_install epel-release
	fi

	package_install ufw

	# Auto-enable a newly installed firewall
	ufw --force enable
	systemctl enable ufw
	systemctl start ufw

	# Auto-add the current user's remote IP to the whitelist (anti-lockout rule)
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		ufw allow from $TTY_IP comment 'Anti-lockout rule based on first install of UFW'
	fi
}

if [ "$THREADS" == "AUTO" ]; then
	let "THREADS=$(nproc --all)-1"
fi

print_header "$GAME_DESC *unofficial* Installer ${INSTALLER_VERSION}"

############################################
## Installer Actions
############################################

##
# Install the game server using Steam
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#   STEAM_ID     - Steam App ID of the game
#   GAME_DESC    - Description of the game (for logging purposes)
#   GAME_SERVICE - Service name to install with Systemd
#   SAVE_DIR     - Directory to store game save files
#   PORT         - Port number the game server will use
#   THREADS	     - Number of threads the game server will use
#   FIREWALL     - Whether to install and configure a firewall (1 = yes, 0 = no)
#
function install_application() {
	print_header "Performing install_application"

	# Create the game user account
	# This will create the account with no password, so if you need to log in with this user,
	# run `sudo passwd $GAME_USER` to set a password.
	if [ -z "$(getent passwd $GAME_USER)" ]; then
		useradd -m -U $GAME_USER
	fi

	# Preliminary requirements
	package_install curl sudo python3-venv

	if [ "$FIREWALL" == "1" ]; then
		if [ "$(get_enabled_firewall)" == "none" ]; then
			# No firewall installed, go ahead and install UFW
			install_ufw
		fi

		firewall_allow --port ${PORT} --udp --comment "${GAME_DESC} Game Port"
	fi

	[ -e "$GAME_DIR/AppFiles" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles"


	# download game, use install_steamcmd, or some other install source
	install_steamcmd

	# Install the management script
	install_management

	# To perform the installation via the game manager, use the following:
	# Use the management script to install the game server
	if ! $GAME_DIR/manage.py --update; then
		echo "Could not install $GAME_DESC, exiting" >&2
		exit 1
	fi

	# Install system service file to be loaded by systemd
    cat > /etc/systemd/system/${GAME_SERVICE}.service <<EOF
[Unit]
# DYNAMICALLY GENERATED FILE! Edit at your own risk
Description=$GAME_DESC
After=network.target

[Service]
Type=simple
LimitNOFILE=10000
User=$GAME_USER
Group=$GAME_USER
WorkingDirectory=$GAME_DIR/AppFiles
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $GAME_USER)
# Only required for games which utilize Proton
#Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_DIR"
ExecStart=$GAME_DIR/AppFiles/PalServer.sh -port=${PORT} -publiclobby -useperfthreads -NoAsyncLoadingThread -UseMuilthreadForDS -NumberOfWorkerThreadsServer=${THREADS}
ExecStop=$GAME_DIR/manage.py --pre-stop --service ${GAME_SERVICE}
ExecStartPost=$GAME_DIR/manage.py --post-start --service ${GAME_SERVICE}
Restart=on-failure
RestartSec=1800s
TimeoutStartSec=600s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload

	if [ -n "$WARLOCK_GUID" ]; then
		# Register Warlock
		[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
		echo -n "$GAME_DIR" > "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

##
# Install the management script from the project's repo
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#
function install_management() {
	print_header "Performing install_management"

	# Install management console and its dependencies
	local SRC=""

	if [[ "$INSTALLER_VERSION" == *"~DEV"* ]]; then
		# Development version, pull from dev branch
		SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/dev/dist/manage.py"
	else
		# Stable version, pull from tagged release
		SRC="https://raw.githubusercontent.com/${REPO}/refs/tags/${INSTALLER_VERSION}/dist/manage.py"
	fi

	if ! download "$SRC" "$GAME_DIR/manage.py"; then
		echo "Could not download management script!" >&2
		exit 1
	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/manage.py"
	chmod +x "$GAME_DIR/manage.py"

	# Install configuration definitions
	cat > "$GAME_DIR/configs.yaml" <<EOF
world:
  - name: Admin Password
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/AdminPassword
    type: str
    help: "Password required to access admin commands in-game."
  - name: Base Camp Max Num In Guild
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/BaseCampMaxNumInGuild
    type: int
    default: 4
    help: "Maximum number of base camps allowed per guild."
  - name: Base Camp Worker Max Num
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/BaseCampWorkerMaxNum
    type: int
    help: "Maximum number of PAL workers allowed per base camp."
  - name: Allow Global Palbox Export
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bAllowGlobalPalboxExport
    type: bool
    help: "If true, allows exporting PAL boxes globally across the server."
  - name: Allow Global Palbox Import
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bAllowGlobalPalboxImport
    type: bool
    help: "If true, allows importing PAL boxes globally across the server."
  - name: Build Area Limit
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bBuildAreaLimit
    type: bool
    help: "Prohibit building near structures such as fast travel"
  - name: Character Recreate in Hardcore
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bCharacterRecreateInHardcore
    type: bool
    help: "If true, allows players to recreate their character upon death in hardcore mode."
  - name: Enable Fast Travel
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bEnableFastTravel
    type: bool
    help: "If true, enables fast travel functionality in the game."
  - name: Enable Invader Enemy
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bEnableInvaderEnemy
    type: bool
    help: "If true, enables invader enemies to spawn in the game world."
  - name: Hardcore
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bHardcore
    type: bool
    help: "If true, enables hardcore mode where players face permanent death."
  - name: Invisible Other Guild Base Camp Area FX
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bInvisibleOtherGuildBaseCampAreaFX
    type: bool
    help: "If true, makes the base camp area effects of other guilds invisible."
  - name: Show Join Left Message
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bIsShowJoinLeftMessage
    type: bool
    help: "If true, displays messages when players join or leave the server."
  - name: Randomizer Pal Level Random
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bIsRandomizerPalLevelRandom
    type: bool
    help: "If true, randomizes the levels of PALs in the game."
  - name: Use Backup Save Data
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bIsUseBackupSaveData
    type: bool
    help: "If true, the server will use backup save data in case of corruption."
  - name: PAL Lost
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bPalLost
    type: bool
    help: "Permanent lost your Pals upon death"
  - name: Show Player List
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/bShowPlayerList
    type: bool
    help: "If true, enables the in-game player list display."
  - name: Build Object Damage Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/BuildObjectDamageRate
    type: float
    default: 1.0
    help: "Multiplier for the damage rate of buildable objects."
  - name: Build Object Deterioration Damage Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/BuildObjectDeteriorationDamageRate
    type: float
    default: 1.0
    help: "Multiplier for the deterioration damage rate of buildable objects."
  - name: Chat Post Limit per Minute
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ChatPostLimitPerMinute
    type: int
    help: "Maximum number of chat messages a player can send per minute."
  - name: Collection Drop Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/CollectionDropRate
    type: float
    default: 1.0
    help: "Multiplier for the drop rate of collection items."
  - name: Collection Object Hp Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/CollectionObjectHpRate
    type: float
    default: 1.0
    help: "Multiplier for the health points of collection objects."
  - name: Collection Object Respawn Speed Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/CollectionObjectRespawnSpeedRate
    type: float
    default: 1.0
    help: "Multiplier for the respawn speed of collection objects."
  - name: Crossplay Platforms
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/CrossplayPlatforms
    type: list
    options:
      - Steam
      - Xbox
      - PS5
      - Mac
    help: "List of platforms allowed to connect to this server"
  - name: Day Time Speed Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/DayTimeSpeedRate
    type: float
    default: 1.0
    help: "Multiplier for the speed of daytime in the game world."
  - name: Death Penalty
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/DeathPenalty
    type: str
    options:
      - None
      - Item
      - ItemAndEquipment
      - All
    help: "Death Penalty dropped items"
  - name: Enemy Drop Item Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/EnemyDropItemRate
    type: float
    default: 1.0
    help: "Multiplier for the drop rate of items from enemies."
  - name: Equipment Durability Damage Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/EquipmentDurabilityDamageRate
    type: float
    default: 1.0
    help: "Multiplier for the durability damage rate of equipment."
  - name: EXP Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ExpRate
    type: float
    default: 1.0
    help: "Multiplier for the experience points gained by players."
  - name: Guild Player Max Num
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/GuildPlayerMaxNum
    type: int
    help: "Maximum number of players allowed in a guild."
  - name: Item Container Force Mark Dirty Interval
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ItemContainerForceMarkDirtyInterval
    type: float
    default: 300.0
    help: "Interval in seconds to force mark item containers as dirty for saving."
  - name: Item Weight Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ItemWeightRate
    type: float
    default: 1.0
    help: "Multiplier for the weight of items carried by players."
  - name: Log Format Type
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/LogFormatType
    type: str
    options:
      - Text
      - Json
    help: "Type of log format to use for server logging."
  - name: Max Building Limit Num
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/MaxBuildingLimitNum
    type: int
    help: "Maximum number of buildings allowed per player."
  - name: Night Time Speed Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/NightTimeSpeedRate
    type: float
    default: 1.0
    help: "Multiplier for the speed of nighttime in the game world."
  - name: Pal Auto HP Regen Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalAutoHPRegeneRate
    type: float
    default: 1.0
    help: "Multiplier for the automatic health regeneration rate of PALs."
  - name: Pal Auto HP Regen Rate in Sleep
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalAutoHpRegeneRateInSleep
    type: float
    default: 1.0
    help: "Multiplier for the automatic health regeneration rate of PALs while sleeping."
  - name: Pal Capture Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalCaptureRate
    type: float
    default: 1.0
    help: "Multiplier for the capture rate of PALs."
  - name: Pal Damage Rate Attack
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalDamageRateAttack
    type: float
    default: 1.0
    help: "Damage from Pals Multiplier"
  - name: Pal Damage Rate Defense
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalDamageRateDefense
    type: float
    default: 1.0
    help: "Damage to Pals Multiplier"
  - name: Pal Egg Default Hatching Time
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalEggDefaultHatchingTime
    type: float
    help: "Default hatching time for PAL eggs in seconds."
  - name: Pal Spawn Num Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalSpawnNumRate
    type: float
    default: 1.0
    help: "Multiplier for the number of PALs that spawn in the game world."
  - name: Pal Stamina Decrease Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalStaminaDecreaceRate
    type: float
    default: 1.0
    help: "Multiplier for the stamina decrease rate of PALs."
  - name: Pal Stomach Decrease Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PalStomachDecreaceRate
    type: float
    default: 1.0
    help: "Multiplier for the stomach decrease rate of PALs."
  - name: Player Auto HP Regen Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PlayerAutoHPRegeneRate
    type: float
    default: 1.0
    help: "Multiplier for the automatic health regeneration rate of players."
  - name: Player Auto HP Regen Rate in Sleep
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PlayerAutoHpRegeneRateInSleep
    type: float
    default: 1.0
    help: "Multiplier for the automatic health regeneration rate of players while sleeping."
  - name: Player Damage Rate Attack
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PlayerDamageRateAttack
    type: float
    default: 1.0
    help: "Damage from Players Multiplier"
  - name: Player Damage Rate Defense
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PlayerDamageRateDefense
    type: float
    default: 1.0
    help: "Damage to Players Multiplier"
  - name: Player Stamina Decrease Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PlayerStaminaDecreaceRate
    type: float
    default: 1.0
    help: "Multiplier for the stamina decrease rate of players."
  - name: Player Stomach Decrease Rate
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PlayerStomachDecreaceRate
    type: float
    default: 1.0
    help: "Multiplier for the stomach decrease rate of players."
  - name: Public IP
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PublicIP
    type: str
    help: "Explicitly specify an external public IP in the community server settings"
  - name: Public Port
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/PublicPort
    type: int
    help: "Explicitly specify the external public port in the community server configuration. (This setting does not change the server's listen port.)"
  - name: Randomizer Seed
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/RandomizerSeed
    type: str
    help: "Seed value for randomizer mode to ensure consistent world generation."
  - name: Randomizer Type
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/RandomizerType
    type: str
    options:
      - None
      - Region
      - All
    help: "Random Pal Mode"
  - name: RCON Enabled
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/RCONEnabled
    type: bool
    help: "If true, enables RCON (Remote Console) access to the server."
  - name: RCON Port
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/RCONPort
    type: int
    help: "Port number for RCON access to the server."
  - name: REST API Enabled
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/RESTAPIEnabled
    type: bool
    help: "If true, enables the REST API for server management."
  - name: REST API Port
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/RESTAPIPort
    type: int
    help: "Port number for the REST API."
  - name: Server Description
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ServerDescription
    type: str
    help: "Description of the server displayed in the server browser."
  - name: Server Name
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ServerName
    type: str
    help: "Name of the server displayed in the server browser."
  - name: Server Password
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ServerPassword
    type: str
    help: "Password required to join the server."
  - name: Server Player Max Num
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ServerPlayerMaxNum
    type: int
    help: "Maximum number of players allowed on the server."
  - name: Server Replicate Pawn Cull Distance
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/ServerReplicatePawnCullDistance
    type: float
    help: "Pal sync distance from player (cm). Min 5000 ~ Max 15000"
  - name: Supply Drop Span
    section: /Script/Pal.PalGameWorldSettings
    key: OptionSettings/SupplyDropSpan
    type: float
    help: "Interval in minutes between supply drops."
manager:
  - name: Shutdown Warning 5 Minutes
    section: Messages
    key: shutdown_5min
    type: str
    default: Server is shutting down in 5 minutes
    help: "Custom message broadcasted to players 5 minutes before server shutdown."
  - name: Shutdown Warning 4 Minutes
    section: Messages
    key: shutdown_4min
    type: str
    default: Server is shutting down in 4 minutes
    help: "Custom message broadcasted to players 4 minutes before server shutdown."
  - name: Shutdown Warning 3 Minutes
    section: Messages
    key: shutdown_3min
    type: str
    default: Server is shutting down in 3 minutes
    help: "Custom message broadcasted to players 3 minutes before server shutdown."
  - name: Shutdown Warning 2 Minutes
    section: Messages
    key: shutdown_2min
    type: str
    default: Server is shutting down in 2 minutes
    help: "Custom message broadcasted to players 2 minutes before server shutdown."
  - name: Shutdown Warning 1 Minute
    section: Messages
    key: shutdown_1min
    type: str
    default: Server is shutting down in 1 minute
    help: "Custom message broadcasted to players 1 minute before server shutdown."
  - name: Shutdown Warning 30 Seconds
    section: Messages
    key: shutdown_30sec
    type: str
    default: Server is shutting down in 30 seconds!
    help: "Custom message broadcasted to players 30 seconds before server shutdown."
  - name: Shutdown Warning NOW
    section: Messages
    key: shutdown_now
    type: str
    default: Server is shutting down NOW!
    help: "Custom message broadcasted to players immediately before server shutdown."
  - name: Instance Started (Discord)
    section: Discord
    key: instance_started
    type: str
    default: "{instance} has started! :rocket:"
    help: "Custom message sent to Discord when the server starts, use '{instance}' to insert the map name"
  - name: Instance Stopping (Discord)
    section: Discord
    key: instance_stopping
    type: str
    default: ":small_red_triangle_down: {instance} is shutting down"
    help: "Custom message sent to Discord when the server stops, use '{instance}' to insert the map name"
  - name: Discord Enabled
    section: Discord
    key: enabled
    type: bool
    default: false
    help: "Enables or disables Discord integration for server status updates."
  - name: Discord Webhook URL
    section: Discord
    key: webhook
    type: str
    help: "The webhook URL for sending server status updates to a Discord channel."
EOF
	chown $GAME_USER:$GAME_USER "$GAME_DIR/configs.yaml"

	# Most games use .settings.ini for manager settings
	touch "$GAME_DIR/.settings.ini"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.settings.ini"

	# If a pyenv is required:
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install pyyaml
}

function postinstall() {
	print_header "Performing postinstall"

	# Ensure configuration file exists, (Palworld doesn't do a great job at filling in incomplete configs)
	[ -d "$GAME_DIR/AppFiles/Pal/Saved/Config/LinuxServer" ] || \
		sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/Pal/Saved/Config/LinuxServer"

	[ -e "$GAME_DIR/AppFiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini" ] || \
		sudo -u $GAME_USER cp "$GAME_DIR/AppFiles/DefaultPalWorldSettings.ini" "$GAME_DIR/AppFiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"

	# First run setup
	$GAME_DIR/manage.py --first-run
}

##
# Uninstall the game server
#
# Expects the following variables:
#   GAME_DIR     - Directory where the game is installed
#   GAME_SERVICE - Service name used with Systemd
#   SAVE_DIR     - Directory where game save files are stored
#
function uninstall_application() {
	print_header "Performing uninstall_application"

	systemctl disable $GAME_SERVICE
	systemctl stop $GAME_SERVICE

	# Service files
	[ -e "/etc/systemd/system/${GAME_SERVICE}.service" ] && rm "/etc/systemd/system/${GAME_SERVICE}.service"

	# Game files
	[ -d "$GAME_DIR" ] && rm -rf "$GAME_DIR/AppFiles"

	# Management scripts
	[ -e "$GAME_DIR/manage.py" ] && rm "$GAME_DIR/manage.py"
	[ -e "$GAME_DIR/configs.yaml" ] && rm "$GAME_DIR/configs.yaml"
	[ -d "$GAME_DIR/.venv" ] && rm -rf "$GAME_DIR/.venv"

	if [ -n "$WARLOCK_GUID" ]; then
		# unregister Warlock
		[ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] && rm "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

############################################
## Pre-exec Checks
############################################

if [ $MODE_UNINSTALL -eq 1 ]; then
	MODE="uninstall"
else
	# Default to install mode
	MODE="install"
fi


if systemctl -q is-active $GAME_SERVICE; then
	echo "$GAME_DESC service is currently running, please stop it before running this installer."
	echo "You can do this with: sudo systemctl stop $GAME_SERVICE"
	exit 1
fi

if [ -n "$OVERRIDE_DIR" ]; then
	# User requested to change the install dir!
	# This changes the GAME_DIR from the default location to wherever the user requested.
	if [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] ; then
		# Check for existing installation directory based on Warlock registration
		GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
		if [ "$GAME_DIR" != "$OVERRIDE_DIR" ]; then
			echo "ERROR: $GAME_DESC already installed in $GAME_DIR, cannot override to $OVERRIDE_DIR" >&2
			echo "If you want to move the installation, please uninstall first and then re-install to the new location." >&2
			exit 1
		fi
	fi

	GAME_DIR="$OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ]; then
	# Check for existing installation directory based on service file
	GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
fi

if [ -e "/etc/systemd/system/${GAME_SERVICE}.service" ]; then
	EXISTING=1
else
	EXISTING=0
fi

############################################
## Installer
############################################


if [ "$MODE" == "install" ]; then

	if [ $SKIP_FIREWALL -eq 1 ]; then
		FIREWALL=0
	elif [ $EXISTING -eq 0 ] && prompt_yn -q --default-yes "Install system firewall?"; then
		FIREWALL=1
	else
		FIREWALL=0
	fi

	install_application

	postinstall

	# Print some instructions and useful tips
    print_header "$GAME_DESC Installation Complete"
fi

if [ "$MODE" == "uninstall" ]; then
	if [ $NONINTERACTIVE -eq 0 ]; then
		if prompt_yn -q --invert --default-no "This will remove all game binary content"; then
			exit 1
		fi
		if prompt_yn -q --invert --default-no "This will remove all player and map data"; then
			exit 1
		fi
	fi

	if prompt_yn -q --default-yes "Perform a backup before everything is wiped?"; then
		$GAME_DIR/manage.py --backup
	fi

	uninstall_application
fi
