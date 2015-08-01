#!/bin/bash

INFORMIX_USER_PASSWORD="informix"
INFORMIX_USER_HOME="/home/informix"
EXTRACT_DIR="/tmp/ifx-install"
CUSTOM_RESPONSE_FILE="$EXTRACT_DIR/ifx-install.responses"
LOG="/tmp/ifx-install.log"

#-------------------------------------------------------------------------------
# Functions.
#-------------------------------------------------------------------------------

fail()
{
    log "$2" >&2
    log "Installation failed. Check the log file in \"$LOG\"." >&2
    exit 1
}

log()
{
    echo "$(date "+%Y-%m-%d %H:%M:%S"): $1" | tee -a $LOG
}

#-------------------------------------------------------------------------------
# Installation should be made by root.
#-------------------------------------------------------------------------------

if [ "$(whoami)" != "root" ]; then
    fail "You need to launch the script as root user."
fi

#-------------------------------------------------------------------------------
# Check for the archive file.
#-------------------------------------------------------------------------------

if [ $# -ne 1 ]; then
    echo "Usage: $(basename $0) <informix-file.tar>";
    exit 1
fi

ARCHIVE="$1"

if ! [ -e "$ARCHIVE" ]; then
    fail "The file \"$ARCHIVE\" does not exists"
fi

#-------------------------------------------------------------------------------
# Informix version detection.
#-------------------------------------------------------------------------------

case "$ARCHIVE" in

    *12.10*)
        IFX_VERSION="12.10"
        RESPONSE_FILE="bundle.properties"
        IFX_INSTALL_ARGS="-i silent -f $CUSTOM_RESPONSE_FILE "
        IFX_INSTALL_ARGS="$IFX_INSTALL_ARGS -DLICENSE_ACCEPTED=TRUE"
        ;;

    *)
        fatal "Unrecognized or not supported Informix version"
        ;;
esac

log "Informix version $IFX_VERSION"

#-------------------------------------------------------------------------------
# Load specific config for the Informix version.
#-------------------------------------------------------------------------------

CONFIG="$(dirname $0)/config/$IFX_VERSION.config"

if ! [ -e "$CONFIG" ]; then
    fail "The config file \"$CONFIG\" does not exist"
fi

source "$CONFIG"

if [ $? -ne 0 ]; then
    fail "Error loading config file \"$CONFIG\""
fi

if [ -e "$INFORMIXDIR" ]; then
    fail "Error the installation directory \"$INFORMIXDIR\" already exists"
fi

if ( grep -Eq "\s+$PORT\/" /etc/services ); then
    fail "The port \"$PORT\" already defined in /etc/services"
fi

#-------------------------------------------------------------------------------
# Dependencies install.
#-------------------------------------------------------------------------------

log "Installing dependencies with apt-get..."

{
    apt-get update -qy \
    && apt-get install -qy apt-utils adduser file sudo
    && apt-get install -qy libaio1 bc pdksh libncurses5 ncurses-bin libpam0g

} &>>$LOG

if [ $? -ne 0 ]; then
    echo "Error installing dependencies"
fi

#-------------------------------------------------------------------------------
# Create informix user if does not exist.
#-------------------------------------------------------------------------------

if ! ( grep -q "^informix:" /etc/passwd ); then

    log "Adding user informix"

    if ! ( useradd -m -d "$INFORMIX_USER_HOME" "informix" &>>$LOG ); then
        fail  "Error creating informix user"
    fi
fi

#-------------------------------------------------------------------------------
# Extract arquive.
#-------------------------------------------------------------------------------

log "Extracting \"$ARCHIVE\" in \"$EXTRACT_DIR\""

{
    mkdir -vp "$EXTRACT_DIR" &&
    tar --overwrite -C "$EXTRACT_DIR" -xf "$ARCHIVE"

} &>>$LOG

if [ $? -ne 0 ]; then
    fail "Error extracting archive"
fi

#-------------------------------------------------------------------------------
# Creation of the responses file.
#-------------------------------------------------------------------------------

case "$IFX_VERSION" in

    12.10)

        {
            echo "USER_INSTALL_DIR=$INFORMIXDIR"
            echo "LICENSE_ACCEPTED=TRUE"
            echo "CHOSEN_FEATURE_LIST=$CHOSEN_FEATURE_LIST"

        } > "$CUSTOM_RESPONSE_FILE"
        ;;
esac

#-------------------------------------------------------------------------------
# Launch install.
#-------------------------------------------------------------------------------

log "Installing Informix in $INFORMIXDIR (this will take some minutes)..."

if ! ( $EXTRACT_DIR/ids_install $IFX_INSTALL_ARGS &>>$LOG ); then
    fail "Error installing Informix"
fi
