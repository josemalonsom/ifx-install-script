#!/bin/bash

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
    echo "$(date "+%Y-%m-%d %H:%M:%S") $1" | tee -a $LOG
}

#-------------------------------------------------------------------------------
# Check that script is running with root user.
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

#-------------------------------------------------------------------------------
# Dependencies install.
#-------------------------------------------------------------------------------

log "Installing dependencies with apt-get..."

{
    apt-get update -qy \
    && apt-get install -qy apt-utils adduser file sudo \
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

#-------------------------------------------------------------------------------
# onconfig file creation.
#-------------------------------------------------------------------------------

log "Creating onconfig file \"$ONCONFIG\""

if ! ( cp -v "$INFORMIXDIR/etc/onconfig.std" "$ONCONFIG" &>>$LOG ); then
    fail "Error creating \"onconfig\" file"
fi

sed -r -i -e "s#^\s*ROOTPATH\s+.*#ROOTPATH $ROOTPATH#" \
          -e "s#^\s*MSGPATH\s+.*#MSGPATH $MSGPATH#" \
          -e "s#^\s*CONSOLE\s+.*#CONSOLE $CONSOLE#" \
          -e "s#^\s*DBSERVERNAME\s+.*#DBSERVERNAME $INFORMIXSERVER#" \
          -e "s#^\s*DEF_TABLE_LOCKMODE\s+.*#DEF_TABLE_LOCKMODE $DEF_TABLE_LOCKMODE#" \
          -e "s#^\s*TAPEDEV\s+.*#TAPEDEV $TAPEDEV#" \
          -e "s#^\s*LTAPEDEV\s+.*#LTAPEDEV $LTAPEDEV#" "$ONCONFIG"

if [ $? -ne 0 ]; then
    fail "Error creating \"onconfig\" file"
fi

if ! ( chown informix.informix "$ONCONFIG" &>>$LOG ); then
    fail "Error changin owner of \"onconfig\" file"
fi

#-------------------------------------------------------------------------------
# sqlhosts file creation.
#-------------------------------------------------------------------------------

log "Creating sqlhosts file \"$SQLHOSTS\""

if ! ( cp -v "$INFORMIXDIR/etc/sqlhosts.std" "$SQLHOSTS" &>>$LOG ); then
    fail "Error creating \"sqlhosts\" file"
fi

SQLHOSTS_CONFIG="${INFORMIXSERVER}\tonsoctcp\tlocalhost\t${SERVICE_NAME}"

sed -r -i -e "s#^\s*demo_on\s+.*#$SQLHOSTS_CONFIG#" "$SQLHOSTS"

if [ $? -ne 0 ]; then
    fail "Error creating \"sqlhosts\" file"
fi

if ! ( chown informix.informix "$SQLHOSTS" &>>$LOG ); then
    fail "Error changin owner of \"sqlhosts\" file"
fi

#-------------------------------------------------------------------------------
# Add port to /etc/services.
#-------------------------------------------------------------------------------

log "Adding port \"$PORT\" to /etc/services"

if ! ( grep -Eq "^${SERVICE_NAME}\s+${PORT}/tcp" /etc/services ); then

    cp -v /etc/services /etc/services.bak &>>$LOG

    SERVICE="${SERVICE_NAME}\t${PORT}/tcp\t\t\t# Informix instance"

    echo -e "$SERVICE" >> /etc/services
fi
