VENV_DIR=".venv"

pushd "${SRCROOT}"

# Check if the virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "No virtual environment found. Creating one..."
    python3 -m venv $VENV_DIR
fi

# Activate the virtual environment
if [ -f "$VENV_DIR/bin/activate" ]; then
    echo "Activating virtual environment..."
    source "$VENV_DIR/bin/activate"
else
    echo "Error: Unable to activate the virtual environment."
fi

if ! [ -x "$(command -v localization_tool)" ]; then
	pip install git+https://gitlabfr.noveogroup.com/internal/localization-tool.git
    #pip install -e ../../localization-tool
fi

localization_tool -c Scripts/L10n/config.yaml
deactivate
popd
