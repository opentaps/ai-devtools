# Setup Instructions
- Create and activate a Python virtual environment:
  ```bash
  python -m venv venv
  source venv/bin/activate  # On Windows use: venv\Scripts\activate
  ```
- Install required packages and generate requirements.txt:
  ```bash
  pip install openai discord-webhook python-dotenv
  ```
- Place the `post-receive` script in your Git repository's `hooks` directory
- Make it executable:
  ```bash
  chmod +x hooks/post-receive
  ```
- Check the `post-receive` script for which branch to monitor (default is `refs/heads/staging`)
- Configure environment variables in the `.env` file for the python script (see `.env.SAMPLE`)
- Create the `code_review/` directory in the repository root
  ```bash
  mkdir code_review
  ```
- Copy the `prompt.txt` to the `code_review/` directory
- Edit the `code-review-cronjob.sh` script to set the `SCRIPT_PATH` at the top of the file
- Add the `code-review-cronjob.sh <git_repo directory>` script to your server's cron jobs, recommended every 5 or 10 minutes

# Key Features
- Queue the commits for processing asynchronously
- Processes each commit individually
- Configurable AI model and endpoint
- Discord mentions via author mapping
- Comprehensive code review prompt
- Error handling for API calls
- Commit message validation
- Diff context preservation (-U1000)

# Prompt Engineering
The prompt includes specific instructions for:
1. Code analysis (security, performance, bugs)
2. Commit message structure validation
3. Ticket number requirements
4. Output formatting
5. Severity level classification

The script will post to Discord in this format:
```
**Code Review for commit abc1234**
Author: @developer
```
Followed by a code block with the AI's review results.

# Testing on a Local Machine

To test the `post-receive` script locally, follow these steps:

## Create a Bare Git Repository
- Create a bare repository to act as the remote:
```bash
mkdir test-repo.git
cd test-repo.git
git init --bare
```
- Add the `post-receive` hook to the bare repository:
```bash
cp /path/to/your/post-receive hooks/
chmod +x hooks/post-receive
cd ..
```

## Create a Test Repository
- Create a new repository to simulate a developer's working directory and add the bare repository as a remote, assuming the two folders are side by side:
```bash
mkdir test-repo
cd test-repo
git init
git remote add origin ../test-repo.git
```

## Push Test Commits
- Make changes to your test repository and commit them:
```bash
echo "Test commit" > test.txt
git add test.txt
git commit -m "Test commit message"
```
- Push the commit to the bare repository to trigger the `post-receive` hook:
```bash
git push origin main
```
- Run the `code-review-cronjob.sh <git_repo directory>` script

## Verify the Output
- Check the log file for the output of the code review, this is in `/tmp/code-reviewer-ai.log` by default unless otherwise specified in `.env`.
- Check the Discord channel or logs to verify that the code review was posted successfully.
- If using a `.env` file, ensure it is correctly configured with your OpenAI API key and Discord webhook URL.

## Debugging
- If the hook doesn’t execute as expected, check the permissions of the `post-receive` script and ensure it is executable.
- Use `echo` statements or logging within the script to debug issues.

This setup allows you to test the `post-receive` hook locally before deploying it to a production environment.
