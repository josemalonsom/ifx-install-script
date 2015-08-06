#!/bin/bash

EXTRACT_DIR="/tmp/ifx-install"
CUSTOM_RESPONSE_FILE="$EXTRACT_DIR/ifx-install.responses"
INIT_FILE="/tmp/ifx-install-initialization.sh"
LOG="/tmp/ifx-install.log"

#-------------------------------------------------------------------------------
# Functions.
#-------------------------------------------------------------------------------

fail()
{
    log "$1" >&2
    log "Installation failed. Check the log file in \"$LOG\"." >&2
    exit 1
}

log()
{
    echo "$(date "+%Y-%m-%d %H:%M:%S") $1" | tee -a $LOG
}

chown_to_informix()
{
    if ! ( chown informix.informix "$1" &>>$LOG ); then
        fail "Error changin owner of \"${1}\" file"
    fi
}

create_directory_as_informix()
{
    if [ -d "$1" ]; then
        return
    fi

    if ( ! sudo -u informix mkdir -p "${1}" &>>$LOG ); then
        fail "Error creating directory \"${1}\""
    fi
}

create_base_directory()
{
    create_directory_as_informix "$(dirname "$1")"
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
# Add port to /etc/services.
#-------------------------------------------------------------------------------

log "Adding port \"$PORT\" to /etc/services"

if ! ( grep -Eq "^${SERVICE_NAME}\s+${PORT}/tcp" /etc/services ); then

    cp -v /etc/services /etc/services.bak &>>$LOG

    SERVICE="${SERVICE_NAME}\t${PORT}/tcp\t\t\t# Informix instance"

    echo -e "$SERVICE" >> /etc/services
fi

#-------------------------------------------------------------------------------
# onconfig file creation.
#-------------------------------------------------------------------------------

ONCONFIG_PATH="$INFORMIXDIR/etc/$ONCONFIG"

log "Creating onconfig file \"$ONCONFIG_PATH\""

if ! ( cp -v "$INFORMIXDIR/etc/onconfig.std" "$ONCONFIG_PATH" &>>$LOG ); then
    fail "Error creating \"onconfig\" file"
fi

sed -r -i -e "s#^ROOTPATH\s+.*#ROOTPATH $ROOTPATH#" \
          -e "s#^ROOTNAME\s+.*#ROOTNAME $ROOTNAME#" \
          -e "s#^MSGPATH\s+.*#MSGPATH $MSGPATH#" \
          -e "s#^CONSOLE\s+.*#CONSOLE $CONSOLE#" \
          -e "s#^DBSERVERNAME\s+.*#DBSERVERNAME $INFORMIXSERVER#" \
          -e "s#^DEF_TABLE_LOCKMODE\s+.*#DEF_TABLE_LOCKMODE $DEF_TABLE_LOCKMODE#" \
          -e "s#^TAPEDEV\s+.*#TAPEDEV $TAPEDEV#" \
          -e "s#^LTAPEDEV\s+.*#LTAPEDEV $LTAPEDEV#" "$ONCONFIG_PATH"

if [ $? -ne 0 ]; then
    fail "Error creating \"onconfig\" file"
fi

chown_to_informix "$ONCONFIG_PATH"

#-------------------------------------------------------------------------------
# sqlhosts file creation.
#-------------------------------------------------------------------------------

log "Creating sqlhosts file \"$INFORMIXSQLHOSTS\""

if ! ( cp -v "$INFORMIXDIR/etc/sqlhosts.std" "$INFORMIXSQLHOSTS" &>>$LOG ); then
    fail "Error creating \"sqlhosts\" file"
fi

INFORMIXSQLHOSTS_CONFIG="${INFORMIXSERVER}\tonsoctcp\tlocalhost\t${SERVICE_NAME}"

sed -r -i -e "s#^\s*demo_on\s+.*#$INFORMIXSQLHOSTS_CONFIG#" "$INFORMIXSQLHOSTS"

if [ $? -ne 0 ]; then
    fail "Error creating \"sqlhosts\" file"
fi

chown_to_informix "$INFORMIXSQLHOSTS"


#-------------------------------------------------------------------------------
# Creation of directories as user informix.
#-------------------------------------------------------------------------------

create_base_directory "$ROOTPATH"
create_base_directory "$MSGPATH"
create_base_directory "$CONSOLE"
create_base_directory "$TAPEDEV"
create_base_directory "$LTAPEDEV"

#-------------------------------------------------------------------------------
# Creation of the primary chunk.
#-------------------------------------------------------------------------------

log "Creating primary chunk \"$ROOTPATH\""

if ! ( touch "$ROOTPATH" && chmod 660 "$ROOTPATH" ); then
    fail "Error creating primary chunk"
fi

chown_to_informix "$ROOTPATH"

#-------------------------------------------------------------------------------
# Create environment file.
#-------------------------------------------------------------------------------

log "Creating environment file \"${ENVIRONMENT_FILE}\""

{
    echo "export INFORMIXSERVER=\"${INFORMIXSERVER}\""
    echo "export INFORMIXDIR=\"${INFORMIXDIR}\""
    echo "export INFORMIXSQLHOSTS=\"${INFORMIXSQLHOSTS}\""
    echo "export INFORMIXTERM=\"terminfo\""
    echo "export ONCONFIG=\"${ONCONFIG}\""
    echo "export CLIENT_LOCALE=\"${CLIENT_LOCALE}\""
    echo "export DB_LOCALE=\"${DB_LOCALE}\""
    echo "export DB_DATE=\"${DBDATE}\""
    echo "export DBDELIMITER=\"${DBDELIMITER}\"";
    echo "export PATH=\"\${INFORMIXDIR}/bin:\${INFORMIXDIR}/lib:\${INFORMIXDIR}/lib/esql:\${PATH}\""
    echo "export LD_LIBRARY_PATH=\"\${INFORMIXDIR}/lib:\$INFORMIXDIR/lib/esql:\${LD_LIBRARY_PATH}\""
    echo "export PS1=\"\u@\h [\${INFORMIXSERVER}]:\w\$\""

} > "$ENVIRONMENT_FILE"

if [ $? -ne 0 ]; then
    fail "Error creating environment file"
fi

chown_to_informix "$ENVIRONMENT_FILE"

#-------------------------------------------------------------------------------
# Initializing Informix server.
#-------------------------------------------------------------------------------

log "Initializing Informix server"

echo ". \"${ENVIRONMENT_FILE}\" && oninit -iy && onstat -m" > "${INIT_FILE}"

sudo -u informix bash "${INIT_FILE}"

if [ $? -ne 0 ]; then
    log "Error initializing Informix server"
fi

rm "${INIT_FILE}" &>/dev/null
