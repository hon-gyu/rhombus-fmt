#!/bin/sh
# Format stdin as Rhombus with the local configuration and queries
here=$(cd "$(dirname "$0")" && pwd)
cd "$here" && exec topiary -C languages.ncl format -l rhombus -q queries/rhombus.scm "$@"
