#!/bin/bash
set -e

BINARY=/home/mik3/apps/files_view_update/filebrowser

# DBus auto-launch service
sudo cp org.lume.FilePicker.service /usr/share/dbus-1/services/

# Desktop entry
sudo cp lume.desktop /usr/share/applications/
sudo update-desktop-database /usr/share/applications/

# Set as default file manager for all the ways apps look it up
xdg-mime default lume.desktop inode/directory

# GNOME / GTK apps check this
gsettings set org.gnome.desktop.default-applications.filemanager lume 2>/dev/null || true

# Thunar/XFCE fallback
xdg-mime default lume.desktop inode/directory application/x-directory

# mimeapps.list — covers most apps that use xdg-open
mkdir -p ~/.config
grep -q "\[Default Applications\]" ~/.config/mimeapps.list 2>/dev/null || echo "[Default Applications]" >> ~/.config/mimeapps.list
sed -i '/^inode\/directory=/d' ~/.config/mimeapps.list
sed -i '/^application\/x-directory=/d' ~/.config/mimeapps.list
echo "inode/directory=lume.desktop" >> ~/.config/mimeapps.list
echo "application/x-directory=lume.desktop" >> ~/.config/mimeapps.list

# update-alternatives so scripts calling x-file-manager get lume
sudo update-alternatives --install /usr/bin/x-file-manager x-file-manager "$BINARY" 100

echo "All done. Test with: xdg-open /home"
