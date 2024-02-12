# this is a installer for the pdfcat command
# it will install the pdfcat either in /usr/local/bin or in
# $HOMEBREW_PREFIX/bin if homebrew is installed

# check if homebrew is installed
if [ -x "$(command -v brew)" ]; then
	INSTALL_PATH=$(brew --prefix)/Cellar/pdfcat
	BIN_PATH=$(brew --prefix)/bin
else
	INSTALL_PATH="/usr/local/share/pdfcat"
	BIN_PATH="/usr/local/bin"
fi

# clone the repository into the install path from github marromlam user and
# pdfcat repository
echo "Installing pdfcat in ${INSTALL_PATH}"
git clone https://github.com/marromlam/pdfcat.git $INSTALL_PATH
pushd $INSTALL_PATH
git checkout devel
popd

# symlink the pdfcat.py to the bin path
echo "Creating symlink to $BIN_PATH"
ln -sf $INSTALL_PATH/termpdf.py $BIN_PATH/pdfcat
echo "Installation complete"
