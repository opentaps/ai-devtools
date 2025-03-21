import os
import subprocess
import openai
import datetime
from discord_webhook import DiscordWebhook
import json

# load the .env
from dotenv import load_dotenv
load_dotenv()

# Configuration from environment variables
API_KEY = os.getenv("API_KEY")
DISCORD_WEBHOOK_URL = os.getenv("DISCORD_WEBHOOK_URL")
MODEL_NAME = os.getenv("MODEL_NAME", "deepseek-reasoner")
API_ENDPOINT = os.getenv("API_ENDPOINT", "https://api.deepseek.com/v1")
AUTHOR_MAPPING = json.loads(os.getenv("AUTHOR_MAPPING", "{}"))  # Map git authors to Discord IDs
LOG_FILE = os.getenv("LOG_FILE", "/tmp/code-reviewer-ai.log")
PROMPT_FILE = os.getenv("PROMPT_FILE", "prompt.txt")
DIFF_CONTEXT = os.getenv("DIFF_CONTEXT", "10")
TEMPERATURE = float(os.getenv("TEMPERATURE", "0.0"))
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "0"))

# check the API_KEY was set
if not API_KEY:
    raise ValueError("API_KEY environment variable is required")

# Set up OpenAI client
client = openai.OpenAI(
    api_key=API_KEY,
    base_url=API_ENDPOINT
)

# this is just an example prompt, you can customize this to your needs
default_prompt = """Perform a GIT code review.

Commit {hash} from {author}

Code Diff:
{diff}

Commit Message:
{subject}
{body}
"""

def log(message, printToConsole=False):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        # some message we also want to print to the console
        if printToConsole:
            print(f"[{timestamp}] {message}")
        f.write(f"[{timestamp}] {message}\n")

def get_commit_info(commit_hash):
    """Extract commit details and diff given the GIT commit hash"""
    cmd = f"git show {commit_hash} --pretty=format:'%H%n%an <%aE>%n%s%n%b' -U{DIFF_CONTEXT}"
    try:
        output = subprocess.check_output(cmd, shell=True, text=True)
        return get_diff_info(output)
    except subprocess.CalledProcessError as e:
        log(f"Error running command [{cmd}]: {e}", printToConsole=True)
        exit(1)

def get_diff_info(diff):
    """Extract the needed fields from the given diff, expecting the format to match GIT output with --pretty=format:'%H%n%an <%aE>%n%s%n%b' """
    parts = diff.split('\n', 3)
    try:
        return {
            "hash": parts[0],
            "author": parts[1],
            "subject": parts[2],
            "body": parts[3].split('\n\n', 1)[0],
            "diff": parts[3].split('\n\n', 1)[1] if '\n\n' in parts[3] else ""
        }
    except IndexError:
        log(f"Error parsing diff (make sure it matches the output of `git diff --pretty=format:'%H%n%an <%aE>%n%s%n%b'`): {diff}", printToConsole=True)
        exit(1)

def analyze_commit(commit_info):
    """Send commit info to AI model for analysis"""
    # find the prompt file
    if os.path.exists(PROMPT_FILE):
        with open(PROMPT_FILE, "r") as f:
            log(f"Loaded prompt from {PROMPT_FILE}")
            prompt = f.read()
    else:
        # default
        log("Using default prompt")
        prompt = default_prompt

    # populate the template
    prompt = prompt.format(**commit_info)

    # collect the response time for the AI model
    start_time = datetime.datetime.now()
    params = {
        'model': MODEL_NAME,
        'messages': [
            {"role": "system", "content": "You are a senior software engineer specializing in Java, python, Golang, typescript, javascript, SQL code reviews.  You are meticulous and detail-oriented, but also prioritize clear and concise feedback."},
            {
                "role": "user",
                "content": prompt
            }
        ],
        'temperature': TEMPERATURE
    }

    if MAX_TOKENS != 0:
        params['max_tokens'] = MAX_TOKENS

    response = client.chat.completions.create(**params)

    end_time = datetime.datetime.now()
    #
    # debug, print the response object excluding the choices
    toPrint = response.__dict__.copy()
    del toPrint['choices']
    log(f"AI Model {MODEL_NAME} - Response: {toPrint}")

    # read the response metadata like number of tokens
    msg = f"AI Model {MODEL_NAME} - Response time: {end_time - start_time}"
    if 'usage' in toPrint:
        msg += f" - Tokens: {response.usage.prompt_tokens} (request) {response.usage.completion_tokens} (response)"
    log(msg)
    return response.choices[0].message.content

def find_discord_id(author):
    # the author is the Git author string which includes the email address
    # we can use this to look up the Discord ID in the AUTHOR_MAPPING
    s1 = author.split("<")
    if len(s1) < 2:
        return ""
    email = s1[1].split(">")[0]
    return AUTHOR_MAPPING.get(email, "")

def notify_discord(commit_info, review):
    """Post review results to Discord"""
    discord_id = find_discord_id(commit_info['author'])
    message = f"**Code Review for commit {commit_info['hash'][:7]}**\n"
    if discord_id:
        message += f"Author: <@{discord_id}>\n"
    else:
        message += f"Author: {commit_info['author']}\n"
    message += f"```\n{review}\n```"

    # Log the message to a file with a timestamp
    log(f"Review result: {message}\n\n")

    if DISCORD_WEBHOOK_URL:
        webhook = DiscordWebhook(
            url=DISCORD_WEBHOOK_URL,
            content=message,
            rate_limit_retry=True
        )
        webhook.execute()


def process_commit(commit_info):
    # log the commit info
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] Processing commit {commit_info['hash']}\n")
        f.write(f"Author: {commit_info['author']}\n")
        f.write(f"Subject: {commit_info['subject']}\n")

    try:
        review = analyze_commit(commit_info)
        # always print the review to the console so the calling script can do something else with it
        print(review)
        notify_discord(commit_info, review)
    except Exception as e:
        log(f"Error processing commit {commit_hash}: {str(e)}", printToConsole=True)
        exit(1)


if __name__ == "__main__":
    # input is either a commit hash given as argument
    # or no argument and the diff is read from stdin
    if len(os.sys.argv) < 2:
        # read the diff from stdin
        diff = os.sys.stdin.read()
        commit_info = get_diff_info(diff)
        process_commit(commit_info)
    elif len(os.sys.argv) == 2:
        commit_hash = os.sys.argv[1]
        commit_info = get_commit_info(commit_hash)
        process_commit(commit_info)
    else:
        log("Bad request: No commit hash provided", printToConsole=True)
        exit(1)
