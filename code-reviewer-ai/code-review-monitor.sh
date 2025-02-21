#!/bin/bash

# Usage: ./code-erview-monitor.sh <path_to_git_repo>

REPO_PATH="$1"

# Get this script directory
SCRIPT_DIR=$(dirname $0)
CACHE_DIR="${SCRIPT_DIR}/.cache"
# make sure the cache directory exists
mkdir -p "$CACHE_DIR"

# Ignore commits that are in those branches
IGNORED_BRANCHES=("local-modifications")

# Sleep time between checks, in seconds
SLEEP_TIME=3

# use the current directory if no path is provided
if [ -z "$REPO_PATH" ]; then
  REPO_PATH=$(pwd)
fi

if [ -z "$REPO_PATH" ]; then
  echo "Usage: $0 <path_to_git_repo>"
  exit 1
fi

if [ ! -d "$REPO_PATH/.git" ]; then
  echo "Error: $REPO_PATH is not a valid git repository."
  exit 1
fi

function get_commit_review() {
    local commit_hash="$1"
    local force_refresh="$2"
    local cache_file

    # check if we have a cached review already for this commit
    # in SCRIPT_DIR/.cache/<commit_hash>
    cache_file="${CACHE_DIR}/${commit_hash}"
    if [ -f "$cache_file" ] && [ -z "$force_refresh" ]; then
        cat "$cache_file"
    else
        # display a temporary message while the review is being fetched
        echo "Fetching review..."
        python ${SCRIPT_DIR}/code-review.py "$commit_hash" > "$cache_file"
        # Remove the temporary message and display the review
        echo -e '\e[1A\e[K'
        cat "$cache_file"
    fi
}

function get_latest_commit() {
  local commit_hash
  local author
  local date
  local message
  local force_refresh="$1"

  commit_hash=$(git --git-dir="$REPO_PATH/.git" log -n 1 --pretty=format:"%H")
  author=$(git --git-dir="$REPO_PATH/.git" log -n 1 --pretty=format:"%an <%ae>")
  date=$(git --git-dir="$REPO_PATH/.git" log -n 1 --pretty=format:"%ad")
  message=$(git --git-dir="$REPO_PATH/.git" log -n 1 --pretty=format:"%s")

  echo -e "Latest Commit:\nHash: $commit_hash\nAuthor: $author\nDate: $date\nMessage: $message\n"

  # find the latest commit, but ignore the heads of the
  # ignored branches
  for branch in "${IGNORED_BRANCHES[@]}"; do
    local branch_commit=$(git --git-dir="$REPO_PATH/.git" show-ref --heads -s "$branch")
    if [ -n "$branch_commit" ]; then
      if [ "$branch_commit" == "$commit_hash" ]; then
        echo "Ignoring commit in branch $branch"
        return
      fi
    fi
  done

  # Display the review
  get_commit_review "$commit_hash" "$force_refresh"
}

function display_commit() {
  local force_refresh="$1"
  clear
  get_latest_commit "$force_refresh"
}

function monitor_repo() {
  local last_commit_hash=""

  while true; do
    local current_commit_hash=$(git --git-dir="$REPO_PATH/.git" log -n 1 --pretty=format:"%H")

    if [ "$current_commit_hash" != "$last_commit_hash" ]; then
      display_commit
      last_commit_hash="$current_commit_hash"
    fi

    if read -t $SLEEP_TIME -n 1 key; then
      case $key in
        q|Q)
          echo "Quitting..."
          exit 0
          ;;
        r|R)
          display_commit "refresh"
          ;;
      esac
    fi
  done
}

pushd $SCRIPT_DIR > /dev/null 2>&1 || exit 1
# Activate the virtual environment for the code review script
source ./venv/bin/activate
# Change to the GIT repository directory
pushd "$REPO_PATH" > /dev/null 2>&1 || exit 1

# Initial display
display_commit

# Start monitoring
monitor_repo
