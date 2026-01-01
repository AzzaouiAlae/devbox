#!/bin/bash

mkdir ~/vsCodeInstaller
wget -O ~/vsCodeInstaller/vsCode.tar.gz  'https://code.visualstudio.com/sha/download?build=stable&os=linux-x64'
tar -xvzf ~/vsCodeInstaller/vsCode.tar.gz -C ~/vsCodeInstaller


gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name "OpenVSCode"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command "~//home/aazzaoui/vsCodeInstaller/VSCode-linux-x64/bin/code-tunnel"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding "<Control><Alt>c"
