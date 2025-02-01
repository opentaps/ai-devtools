# Path to the code-review.py script (configurable)
SCRIPT_PATH="/path/to/code-reviewer-ai"

# Ensure the script path and venv path are set
if [ -z "$SCRIPT_PATH" ]; then
    echo "Error: SCRIPT_PATH is not configured."
    exit 1
fi

# ensure the script can be found
if [ ! -f "$SCRIPT_PATH/code-review.py" ]; then
    echo "Error: code-review.py script not found in $SCRIPT_PATH"
    exit 1
fi

# ensure the virtual environment is present and can be activated
if [ ! -d "$SCRIPT_PATH/venv" ]; then
    echo "Error: Virtual environment not found in $SCRIPT_PATH/venv"
    exit 1
fi

# Check if the repository path is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <git_repo_dir>"
    exit 1
fi

GIT_REPO_DIR="$1"
QUEUE_DIR="$GIT_REPO_DIR/code_review/queue"
RESULT_DIR="$GIT_REPO_DIR/code_review/results"

# Ensure the queue directory exists
if [ ! -d "$QUEUE_DIR" ]; then
    echo "Queue directory $QUEUE_DIR does not exist."
    exit 0
fi

# Ensure the results directory exists, create it if it doesn't
if [ ! -d "$RESULT_DIR" ]; then
    mkdir -p "$RESULT_DIR"
fi

# go to the repository directory, this is needed for the code-review script
cd "$GIT_REPO_DIR"

# Process each file in the queue
for FILE in "$QUEUE_DIR"/*; do
    if [ -f "$FILE" ]; then
        COMMIT_HASH=$(cat "$FILE")
        # Activate the virtual environment and run the code-review script
        source "$SCRIPT_PATH/venv/bin/activate"
        # run python script, save the result and dequeue the file
        python "$SCRIPT_PATH/code-review.py" "$COMMIT_HASH" > ${RESULT_DIR}/${COMMIT_HASH} && rm "$FILE"
        deactivate
    fi
done
