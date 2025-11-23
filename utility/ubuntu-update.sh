#!/bin/bash

# Refresh package lists
sudo apt update

# Upgrade all upgradable packages (safe)
sudo apt upgrade -y

# Do a full upgrade to allow package removals/changes (optional but recommended)
sudo apt full-upgrade -y

# Remove no-longer-needed packages and cached archives
sudo apt autoremove -y
sudo apt autoclean

# Refresh snaps (if you use snaps)
sudo snap refresh