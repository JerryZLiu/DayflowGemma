You're working in a macOS app in Xcode called Dayflow.
You are not able to build/run the app. if you need the app to be built/run/tested, please notify the user of what needs to be done, so they can complete it.
Remember, you can directly access the sqlite db, to help debug.

Your role

Your role is to write code. You do NOT have access to the running app, so you cannot test the code. You MUST rely on me, the user, to test the code.

If I report a bug in your code, after you fix it, you should pause and ask me to verify that the bug is fixed.

You do not have full context on the project, so often you will need to ask me questions about how to proceed.

Don't be shy to ask questions -- I'm here to help you!

If I send you a URL, you MUST immediately fetch its contents and read it carefully, before you do anything else.



## Database Location
The SQLite database is located at:
`/Users/jerry/Library/Containers/teleportlabs.com.Dayflow/Data/Library/Application Support/Dayflow/recordings/chunks.sqlite`

You can query it directly using:
```bash
sqlite3 "/Users/jerry/Library/Containers/teleportlabs.com.Dayflow/Data/Library/Application Support/Dayflow/recordings/chunks.sqlite" "YOUR SQL QUERY"
``` 

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
NEVER create extensions on classes that need to access private properties. Instead, add the methods directly to the class for proper encapsulation. 
ALWAYS ASK THE USER FOR PERMISSION, BEFORE WRITING ANY CODE, IF THE USER ASKS FOR SOMETHING, NEVER JUST STRAIGHT TO CODE, UNLESS THEY SAY EXPLICITLY. INSTEAD EXPLAIN YOUR THOUGHTS AND GIVE A HIGH LEVEL OVERVIEW OF YOUR PLAN. SIMPLE PSEUDOCODE IS GOOD TOO
NEVER DO ANY DESTRUCTIVE GIT CHANGES WITHOUT EXPLICIT PERMISSION
ALWAYS READ THE ENTIRE FILE, INSTEAD OF READING PART OF THE FILE. ALWAYS GATHER AS MUCH CODE CONTEXT AS POSSIBLE BEFORE PLANNING/CODING. DO NOT BE LAZY.
