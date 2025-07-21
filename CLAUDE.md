You're working in a macOS app in Xcode called Dayflow.
You are not able to build/run the app. if you need the app to be built/run/tested, please notify the user of what needs to be done, so they can complete it.
Remember, you can directly access the sqlite db, to help debug.

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
