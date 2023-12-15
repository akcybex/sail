#!/usr/bin/env bash

UNAMEOUT="$(uname -s)"

# Verify operating system is supported...
case "${UNAMEOUT}" in
    Linux*)             MACHINE=linux;;
    Darwin*)            MACHINE=mac;;
    *)                  MACHINE="UNKNOWN"
esac

if [ "$MACHINE" == "UNKNOWN" ]; then
    echo "Unsupported operating system [$(uname -s)]. This script supports macOS and Linux." >&2
    exit 1
fi

# Determine if stdout is a terminal...
if test -t 1; then
    # Determine if colors are supported...
    ncolors=$(tput colors)
    if test -n "$ncolors" && test "$ncolors" -ge 8; then
        BOLD="$(tput bold)"
        YELLOW="$(tput setaf 3)"
        GREEN="$(tput setaf 2)"
        NC="$(tput sgr0)"
    fi
fi

# Function that prints the available commands...
function display_help {
    echo "WordPress Docker Script"
    echo
    echo "${YELLOW}Usage:${NC}" >&2
    echo "  wp-docker COMMAND [options] [arguments]"
    echo
    echo "Unknown commands are passed to the docker-compose binary."
    echo
    echo "${YELLOW}Docker Compose Commands:${NC}"
    echo "  ${GREEN}wp-docker up${NC}        Start the WordPress environment"
    echo "  ${GREEN}wp-docker up -d${NC}     Start the WordPress environment in the background"
    echo "  ${GREEN}wp-docker stop${NC}      Stop the WordPress environment"
    echo "  ${GREEN}wp-docker restart${NC}   Restart the WordPress environment"
    echo "  ${GREEN}wp-docker ps${NC}        Display the status of all containers"
    echo
    echo "${YELLOW}WP CLI Commands:${NC}"
    echo "  ${GREEN}wp-docker wp ...${NC}    Run a WP CLI command"
    echo
    echo "${YELLOW}Database Commands:${NC}"
    echo "  ${GREEN}wp-docker mysql${NC}     Start a MySQL CLI session within the 'mysql' container"
    echo
    echo "${YELLOW}Container CLI:${NC}"
    echo "  ${GREEN}wp-docker shell${NC}     Start a shell session within the WordPress container"
    echo "  ${GREEN}wp-docker bash${NC}      Alias for 'wp-docker shell'"
    echo
    echo "${YELLOW}Customization:${NC}"
    echo "  ${GREEN}wp-docker build --no-cache${NC}       Rebuild all of the WordPress containers"

    exit 1
}

# Proxy the "help" command...
if [ $# -gt 0 ]; then
    if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "-help" ] || [ "$1" == "--help" ]; then
        display_help
    fi
else
    display_help
fi

# Define Docker Compose command prefix...
docker compose &> /dev/null
if [ $? == 0 ]; then
    DOCKER_COMPOSE=(docker compose)
else
    DOCKER_COMPOSE=(docker-compose)
fi

# Define environment variables...
export WP_PORT=${WP_PORT:-80}
export DB_PORT=${DB_PORT:-3306}
export WWWUSER=${WWWUSER:-$UID}
export WWWGROUP=${WWWGROUP:-$(id -g)}

# Function that outputs WordPress Docker is not running...
function wp_docker_is_not_running {
    echo "${BOLD}WordPress Docker is not running.${NC}" >&2
    echo "" >&2
    echo "${BOLD}You may start WordPress Docker using the following command: './wp-docker up' or './wp-docker up -d'" >&2

    exit 1
}

EXEC="yes"

# Ensure that Docker is running...
if ! docker info > /dev/null 2>&1; then
    echo "${BOLD}Docker is not running.${NC}" >&2
    exit 1
fi

# Determine if WordPress Docker is currently up...
if "${DOCKER_COMPOSE[@]}" ps wordpress 2>&1 | grep 'Exit\|exited'; then
    echo "${BOLD}Shutting down old WordPress Docker processes...${NC}" >&2
    "${DOCKER_COMPOSE[@]}" down > /dev/null 2>&1
    EXEC="no"
elif [ -z "$("${DOCKER_COMPOSE[@]}" ps -q)" ]; then
    EXEC="no"
fi

ARGS=()

# Proxy WP CLI commands to the WordPress container...
if [ "$1" == "wp" ]; then
    shift 1
    if [ "$EXEC" == "yes" ]; then
        ARGS+=(exec -u www-data)
        [ ! -t 0 ] && ARGS+=(-T)
        ARGS+=("wordpress" "wp" "$@")
    else
        wp_docker_is_not_running
    fi

# Proxy MySQL commands to the MySQL container...
elif [ "$1" == "mysql" ]; then
    shift 1
    if [ "$EXEC" == "yes" ]; then
        ARGS+=(exec)
        [ ! -t 0 ] && ARGS+=(-T)
        ARGS+=(mysql bash -c)
        ARGS+=("MYSQL_PWD=\${MYSQL_PASSWORD} mysql -u \${MYSQL_USER} \${MYSQL_DATABASE}")
    else
        wp_docker_is_not_running
    fi

# Initiate a Bash shell within the WordPress container...
elif [ "$1" == "shell" ] || [ "$1" == "bash" ]; then
    shift 1
    if [ "$EXEC" == "yes" ]; then
        ARGS+=(exec -u www-data)
        [ ! -t 0 ] && ARGS+=(-T)
        ARGS+=("wordpress" bash "$@")
    else
        wp_docker_is_not_running
    fi

# Pass unknown commands to the "docker-compose" binary...
else
    ARGS+=("$@")
fi

# Run Docker Compose with the defined arguments...
"${DOCKER_COMPOSE[@]}" "${ARGS[@]}"
