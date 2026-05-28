#!/bin/bash

# Thread Setup Script

set -euo pipefail

# --- Constants ---
VERSION=$(tr -d '[:space:]' < VERSION)
MIN_PYTHON_VERSION="3.10"
MIN_CMAKE_VERSION="3.10"

# --- Colors ---
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }

check_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		log_error "Command not found: $1"
		return 1
	fi
}

version_compare() {
	local version=$1
	local min_version=$2
	[ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n1)" = "$min_version" ]
}

# --- Main Setup ---
log_info "Starting Thread Setup v$VERSION"

# --- Platform Detection ---
case "$(uname -s)" in
Darwin*)
	PLATFORM="macos"
	PACKAGE_MANAGER="brew"
	;;
Linux*)
	if [ -f /etc/os-release ]; then
		. /etc/os-release
		if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
			PLATFORM="linux"
			PACKAGE_MANAGER="apt"
		else
			log_error "Unsupported Linux distribution: $ID"
			exit 1
		fi
	else
		log_error "Could not determine Linux distribution"
		exit 1
	fi
	;;
CYGWIN* | MINGW* | MSYS*)
	PLATFORM="windows"
	PACKAGE_MANAGER="choco"
	;;
*)
	log_error "Unsupported platform: $(uname -s)"
	exit 1
	;;
esac

log_info "Detected platform: $PLATFORM ($(uname -s))"

# --- Dependency Installation ---
install_dependencies() {
	log_info "Installing system dependencies..."

	case "$PLATFORM" in
	"macos")
		# Check for Homebrew
		if ! check_command brew; then
			log_error "Homebrew is required. Please install from https://brew.sh"
			exit 1
		fi

		brew install cmake ninja

		if ! xcode-select -p &>/dev/null; then
			log_info "Installing Xcode Command Line Tools..."
			xcode-select --install
			log_warn "Please complete Xcode installation and run this script again"
			exit 0
		fi

		if [ "${WITH_METAL:-OFF}" = "ON" ]; then
			sudo xcodebuild -license accept
			xcodebuild -downloadComponent MetalToolchain
		fi

		if [ "${INSTALL_NATIVE_OPENCV:-false}" = true ]; then
			brew install opencv
		fi
		;;

	"linux")
		if [ "$(id -u)" -ne 0 ]; then
			sudo -v || {
				log_error "Need sudo access to install packages"
				exit 1
			}
		fi

		# Avoid interactive prompts
		export DEBIAN_FRONTEND=noninteractive
		export TZ=UTC

		# Update package lists
		sudo apt-get update -y

		sudo apt-get install -y --no-install-recommends \
			build-essential \
			cmake \
			ninja-build \
			wget \
			git \
			python3 \
			python3-pip \
			python3-venv

		if [ "${INSTALL_NATIVE_OPENCV:-false}" = true ]; then
			sudo apt-get install -y --no-install-recommends \
				libopencv-dev \
				libtbb2 \
				libtbb-dev \
				libjpeg-dev \
				libpng-dev \
				libtiff-dev \
				libavformat-dev \
				libpq-dev
		fi

		# Install CUDA if requested
		if [ "${INSTALL_CUDA:-false}" = true ]; then
			log_info "Installing CUDA toolkit..."
			TMP_CUDA="/tmp/cuda-keyring.deb"
			wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O "$TMP_CUDA"
			sudo dpkg -i "$TMP_CUDA"
			sudo apt-get update -y
			sudo apt-get install -y cuda-toolkit-12-6 ||
				log_warn "CUDA installation failed. Continuing without CUDA support."
			rm -f "$TMP_CUDA"
		fi
		;;

	"windows")
		if ! check_command choco; then
			log_error "Chocolatey is required. Please install from https://chocolatey.org"
			exit 1
		fi

		choco install -y \
			cmake \
			ninja \
			python3 \
			git

		if [ "${INSTALL_NATIVE_OPENCV:-false}" = true ]; then
			choco install -y vcpkg
			VCPKG_ROOT="C:\\vcpkg"
			export PATH="$VCPKG_ROOT:$PATH"
			vcpkg install \
				opencv[core,contrib,jpeg,png,tiff,webp]:x64-windows \
				tbb:x64-windows
		fi
		;;
	esac
}

# --- Python Setup ---
setup_python() {
	log_info "Setting up Python environment..."

	# Check Python version
	if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)"; then
		log_error "Python $MIN_PYTHON_VERSION or higher is required"
		exit 1
	fi

	# Create and activate virtual environment
	if [ ! -d "venv" ]; then
		python3 -m venv venv
	fi

	# Activate virtual environment
	if [ -f "venv/bin/activate" ]; then
		source venv/bin/activate
	elif [ -f "venv/Scripts/activate" ]; then
		source venv/Scripts/activate
	else
		log_warn "Could not activate virtual environment. Using system Python."
	fi

	# Upgrade pip and install requirements
	pip install --upgrade pip
	pip install -r requirements.txt

	# Install development tools
	pip install \
		pytest \
		pytest-cov \
		ruff \
		black \
		mypy \
		pylint \
		pre-commit

	# Setup pre-commit hooks
	git config --global --unset core.hooksPath || true
	pre-commit install
}

# --- Main Execution ---
main() {
	install_dependencies
	setup_python

	log_success "Setup completed successfully!"
	log_info "To activate the virtual environment, run:"
	echo "  source venv/bin/activate  # On Unix/macOS"
	echo "  .\\venv\\Scripts\\activate  # On Windows"
}

main "$@"
